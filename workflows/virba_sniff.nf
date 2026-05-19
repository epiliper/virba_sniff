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
    ch_samplesheet              // channel: samplesheet read in from --input
    fastp_adapter_fasta         // path
    kraken2_host_db             // path

    skip_fastp

    // TODO
    _kraken2_save_host          // path

    kraken2_bacteria_db         // path
    kraken2_virus_db            // path

    virus_assembly_taxonids     // path
    virus_assembly_db           // path

    min_assembly_coverage      // float
    min_assembly_depth         // float

    outdir

    main:

    def VIRUS_NCBI_TAXID = channel.value([name: "viruses", id: 10239])
    def BACTERIA_NCBI_TAXID = channel.value([name: "bacteria", id: 2])
    def ch_versions = channel.empty()

    ch_samplesheet.set { main_ch }

    def kraken2_dbs = []

    if (kraken2_bacteria_db) {
            kraken2_dbs += kraken2_bacteria_db
        } else {
                log.warn("No kraken2 bacterial database given. Analysis will not cover bacteria.")
            }

    if (kraken2_virus_db) {
            kraken2_dbs += kraken2_virus_db
        } else {
                log.warn("No kraken2 virus database given. Analysis will not cover viruses.")
            }

    if (!virus_assembly_db) {
            log.warn("No virus assembly database supplied. Viruses will not be de-novo assembled")
        }

    // BEGIN MAIN WORKFLOW

    // TODO: check adapters used here
    if (!skip_fastp) {
        FASTP(main_ch.combine(channel.value(fastp_adapter_fasta)), false, false, false)
        FASTP.out.reads.set { main_ch }
    }

    if (kraken2_host_db) {
            KRAKEN2_REMOVE_HOST(main_ch, kraken2_host_db, false, false)
            KRAKEN2_REMOVE_HOST.out.unclassified_reads_fastq.set { main_ch }
        }

    KRAKEN2_CLASSIFY(main_ch, kraken2_virus_db, false, false)

    KRAKEN2_CLASSIFY.out.classified_reads_assignment
        .join(KRAKEN2_CLASSIFY.out.classified_reads_fastq)
        .join(KRAKEN2_CLASSIFY.out.report).set { classify_ch }

    // level 1: extract lineages
    if (virus_assembly_db) {
        KRAKEN_EXTRACT_VIRUSES(classify_ch.combine(VIRUS_NCBI_TAXID), false, true)


        KRAKEN_EXTRACT_VIRUSES.out.extracted_kraken2_reads.map { meta, reads, _tid -> [ meta, reads ]}
            .join(KRAKEN2_CLASSIFY.out.classified_reads_assignment)
            .join(KRAKEN2_CLASSIFY.out.report)
            .map { meta, reads, asn, report -> [ meta, asn, reads, report ]}
            .set { vir_ch }


        VIRUSES(vir_ch, virus_assembly_db, virus_assembly_taxonids, min_assembly_coverage, min_assembly_depth)
    }

    KRAKEN_EXTRACT_BACTERIA(classify_ch.combine(BACTERIA_NCBI_TAXID), false, true)


    // KRAKEN_EXTRACT_BACTERIA.out.extracted_kraken2_reads
    //     .join(KRAKEN2_CLASSIFY.out.classified_reads_assignment)
    //     .join(KRAKEN2_CLASSIFY.out.report)
    //     .map { meta, reads, assign, report, _tid -> [ meta, reads, assign, report ]}
    //     .set { bac_ch }


    // BACTERIA(bac_ch)
    // }

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
