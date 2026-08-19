/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    IMPORT MODULES / SUBWORKFLOWS / FUNCTIONS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/
include { paramsSummaryMap } from 'plugin/nf-schema'
include { softwareVersionsToYAML } from '../subworkflows/nf-core/utils_nfcore_pipeline'
include { methodsDescriptionText } from '../subworkflows/local/utils_nfcore_virba_sniff_pipeline'

include { KRAKEN2_KRAKEN2 as KRAKEN2_REMOVE_HOST } from '../modules/nf-core/kraken2/kraken2/main'
include { KRAKEN2_KRAKEN2 as KRAKEN2_CLASSIFY } from '../modules/nf-core/kraken2/kraken2/main'
include { KUNPENG_CLASSIFY } from '../modules/local/kunpeng_classify.nf'

include { BBMAP_BBDUK } from '../modules/local/bbduk'
include { MINIMAP2_BIG } from '../modules/local/minimap2'
include { MINIMAP2_BIG as MINIMAP2_CONTAM } from '../modules/local/minimap2'
include { BAMTAX_NAMES } from '../modules/local/bamtax_names'
include { SAMTOOLS_FILTER_TO_BAM } from '../modules/local/samtools_filter_to_bam'

include { KMA_ALIGN_PARTITION } from '../modules/local/kma_aln_part'
include { KMA_MERGE_ALIGNMENTS } from '../modules/local/kma_merge_alns'

include { FASTP } from '../modules/nf-core/fastp/main'
include { KRAKENTOOLS_EXTRACTKRAKENREADS as KRAKEN_EXTRACT_VIRUSES } from '../modules/nf-core/krakentools/extractkrakenreads/main'
include { KRAKENTOOLS_EXTRACTKRAKENREADS as KRAKEN_EXTRACT_BACTERIA } from '../modules/nf-core/krakentools/extractkrakenreads/main'

include { VIRUSES } from '../subworkflows/local/viruses'
// include { BACTERIA } from '../subworkflows/local/bacteria'


/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    RUN MAIN WORKFLOW
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

workflow VIRBA_SNIFF {
    take:
    ch_samplesheet // channel: samplesheet read in from --input
    fastp_adapter_fasta // path
    skip_fastp // boolean
    ref_idx // path
    contam_idx // path
    outdir // path

    main:

    // begin: detect kma index partitions
    ////////////////////////////////////
    def dbDir = ref_idx.toString().replaceFirst('/+$', '')
    def usesS3Mount = dbDir.startsWith('/mnt/s3/')
    def lookupDir = usesS3Mount ? dbDir.replaceFirst('^/mnt/s3/', 's3://') : dbDir
    def dbGlob = "${lookupDir}/*.fasta_*"
    def isS3 = lookupDir.startsWith('s3://')

    dbFiles = isS3
        ? Channel.fromPath(dbGlob)
        : Channel.fromPath(dbGlob, checkIfExists: true)

    db_ch = dbFiles
        .map { file ->
            def match = file.name =~ /^(.+\.fasta_(\d+))\.(comp\.b|length\.b|name|seq\.b)$/

            if (!match.matches()) {
                error("Unexpected database file: ${file}")
            }

            tuple(
                match.group(2) as Integer,
                match.group(1),
                file,
            )
        }
        .groupTuple(by: [0, 1])
        .map { index, basename, files ->
            if (files.size() != 4) {
                error("Partition ${index} has ${files.size()} files; expected 4")
            }

            tuple(index, basename, files.sort { it.toString() })
        }

    // db_ch.view { index, basename, files ->
    //     "KMA DB partition: index=${index}, basename=${basename}, files=${files.join(', ')}"
    // }

    ///////////////////////////////////
    // end: detect kma index partitions

    def ch_versions = channel.empty()

    ch_samplesheet.set { main_ch }

    // TODO: check adapters used here
    if (!skip_fastp) {
        FASTP(main_ch.combine(channel.value(fastp_adapter_fasta), by: 0), false, false, false)
        FASTP.out.reads.set { main_ch }
    }

    BBMAP_BBDUK(main_ch)
    BBMAP_BBDUK.out.reads.set { main_ch }

    if (contam_idx) {
        MINIMAP2_CONTAM(main_ch, contam_idx, true, "contam", false)
        BAMTAX_NAMES(MINIMAP2_CONTAM.out.bam)
    }

    // create channel combining each input fastq with all db partitions
    // { meta, fastq(s), db_meta, db_file }
    main_ch.combine(db_ch).set { aln_jobs }

    // align all input fastas to each partition
    KMA_ALIGN_PARTITION(aln_jobs)


    main_ch
        .combine(KMA_ALIGN_PARTITION.out.kma_files, by: 0)
        .groupTuple(by: 0)
        .set { fastq_kma }

    fastq_kma.view { contents -> "contents: ${contents}" }


    db_ch
        .multiMap { _meta, db_names, db_paths ->
            db_names: db_names
            db_paths: db_paths
        }
        .set { db_split_ch }

    // for each input fastq, reduce alignments to one output across all db partitions
    KMA_MERGE_ALIGNMENTS(
        fastq_kma,
        db_split_ch.db_names.collect(),
        db_split_ch.db_paths.collect(),
        false,
        false,
    )

    // MINIMAP2_BIG(main_ch, ref_idx, false, "ref", true)

    if (contam_idx) {
        SAMTOOLS_FILTER_TO_BAM(
            KMA_MERGE_ALIGNMENTS.out.bam.join(BAMTAX_NAMES.out.qnames),
            true,
        )

        SAMTOOLS_FILTER_TO_BAM.out.decontam.set { main_ch }
    }
    // END MAIN WORKFLOW

    //
    // Collate and save software versions
    //
    def topic_versions = channel.topic("versions")
        .distinct()
        .branch { entry ->
            versions_file: entry instanceof Path
            versions_tuple: true
        }

    def topic_versions_string = topic_versions.versions_tuple
        .map { process, tool, version ->
            [process[process.lastIndexOf(':') + 1..-1], "  ${tool}: ${version}"]
        }
        .groupTuple(by: 0)
        .map { process, tool_versions ->
            tool_versions.unique().sort()
            "${process}:\n${tool_versions.join('\n')}"
        }

    def ch_collated_versions = softwareVersionsToYAML(ch_versions.mix(topic_versions.versions_file))
        .mix(topic_versions_string)
        .collectFile(
            storeDir: "${outdir}/pipeline_info",
            name: 'virba_sniff_software_' + 'versions.yml',
            sort: true,
            newLine: true,
        )

    emit:
    versions = ch_versions // channel: [ path(versions.yml) ]
}
