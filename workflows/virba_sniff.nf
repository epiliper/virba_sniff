/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    IMPORT MODULES / SUBWORKFLOWS / FUNCTIONS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/
include { paramsSummaryMap       } from 'plugin/nf-schema'
include { softwareVersionsToYAML } from '../subworkflows/nf-core/utils_nfcore_pipeline'
include { methodsDescriptionText } from '../subworkflows/local/utils_nfcore_virba_sniff_pipeline'

include { KRAKEN2_KRAKEN2 as KRAKEN2_REMOVE_HOST } from '../modules/nf-core/kraken2/kraken2/main'
include { KRAKEN2_KRAKEN2 as KRAKEN2_CLASSIFY    } from '../modules/nf-core/kraken2/kraken2/main'

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
    ch_samplesheet      // channel: samplesheet read in from --input
    kraken2_host_db     // path

    // TODO
    _kraken2_save_host   // path

    taxon_bac_db        // path

    taxon_vir_db        // path
    taxon_vir_ids       // path

    outdir

    main:

    def VIRUS_NCBI_TAXID = "10239"
    def BACTERIA_NCBI_TAXID = "2"


    def ch_versions = channel.empty()

    ch_samplesheet.set { main_ch }

    // BEGIN MAIN WORKFLOW

    // TODO: check adapters used here
    FASTP(main_ch, false, false, false).set { main_ch }

    if (kraken2_host_db) {
            KRAKEN2_REMOVE_HOST(ch_samplesheet, kraken2_host_db, false, false)
            KRAKEN2_REMOVE_HOST.out.unclassified_reads_fastq.set { main_ch }
        }

    KRAKEN2_CLASSIFY(main_ch, [taxon_bac_db, taxon_vir_db], false, false)

    KRAKEN2_CLASSIFY.out.classified_reads_assignment
        .join(KRAKEN2_CLASSIFY.out.classified_reads_fastq)
        .join(KRAKEN2_CLASSIFY.out.report).set { classify_ch }

    // level 1: extract lineages
    KRAKEN_EXTRACT_VIRUSES(classify_ch.combine(VIRUS_NCBI_TAXID))
    KRAKEN_EXTRACT_BACTERIA(classify_ch.combine(BACTERIA_NCBI_TAXID))

    KRAKEN_EXTRACT_VIRUSES.out.extracted_kraken2_reads
        .join(KRAKEN2_CLASSIFY.out.classified_reads_assignment)
        .join(KRAKEN2_CLASSIFY.out.report)
        .map { meta, reads, assign, report, _tid -> [ meta, reads, assign, report ]}
        .set { vir_ch }

    // KRAKEN_EXTRACT_BACTERIA.out.extracted_kraken2_reads
    //     .join(KRAKEN2_CLASSIFY.out.classified_reads_assignment)
    //     .join(KRAKEN2_CLASSIFY.out.report)
    //     .map { meta, reads, assign, report, _tid -> [ meta, reads, assign, report ]}
    //     .set { bac_ch }

    VIRUSES(vir_ch, taxon_vir_db, taxon_vir_ids)

    // BACTERIA(bac_ch)


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
            [ process[process.lastIndexOf(':')+1..-1], "  ${tool}: ${version}" ]
        }
        .groupTuple(by:0)
        .map { process, tool_versions ->
            tool_versions.unique().sort()
            "${process}:\n${tool_versions.join('\n')}"
        }

    def ch_collated_versions = softwareVersionsToYAML(ch_versions.mix(topic_versions.versions_file))
        .mix(topic_versions_string)
        .collectFile(
            storeDir: "${outdir}/pipeline_info",
            name:  'virba_sniff_software_'  + 'versions.yml',
            sort: true,
            newLine: true
        )
    emit:
    versions       = ch_versions                 // channel: [ path(versions.yml) ]
}

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    THE END
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/
