include { KRAKENTOOLS_EXTRACTKRAKENREADS as KRAKEN_EXTRACT_SUBTAXA } from '../../modules/nf-core/krakentools/extractkrakenreads'
include { MEGAHIT } from '../../modules/nf-core/megahit/main'
include { KMA_INDEX } from '../../modules/nf-core/kma/index/main'
include { KMA_KMA } from '../../modules/nf-core/kma/kma/main'
include { SELECT_BEST_KMA_REF } from '../../modules/local/select_best_kma_ref'

include { BWA_INDEX as BWA_INDEX_REF } from '../../modules/nf-core/bwa/index/main'
include { BWA_INDEX as BWA_INDEX_1 } from '../../modules/nf-core/bwa/index/main'
include { BWA_INDEX as BWA_INDEX_2 } from '../../modules/nf-core/bwa/index/main'

include { BWA_MEM as BWA_MEM_REF } from '../../modules/nf-core/bwa/mem/main'
include { BWA_MEM as BWA_MEM_1  } from '../../modules/nf-core/bwa/mem/main'
include { BWA_MEM as BWA_MEM_2  } from '../../modules/nf-core/bwa/mem/main'

include { IVAR_CONSENSUS as IVAR_CONSENSUS_1 } from '../../modules/nf-core/ivar/consensus/main'
include { IVAR_CONSENSUS as IVAR_CONSENSUS_2 } from '../../modules/nf-core/ivar/consensus/main'

include { CREATE_SCAFFOLD } from '../../modules/local/create_scaffold'

workflow VIRUSES {
    take: 
    classified_reads  // tuple val(meta), path(extracted_reads), path(assignment), path(report), lineage-level reads
    taxon_virus_db    // path to virus fasta db
    taxids            // path to taxonid list

    main:
    channel.value([[id: file(taxon_virus_db).baseName], taxon_virus_db]).set { virus_db_ch }
    KMA_INDEX(virus_db_ch).set { kma_idx_ch }

    // 1. attempt to generate FASTQs for each taxonid in our list 
    channel.of(taxids.splitCsv(sep: "\t", header: false, strip: true).map { row -> [ taxid: row[0], name: row[1] ] }).set { tid_ch }
    classified_reads.combine(tid_ch).set { extract_input_ch }

    KRAKEN_EXTRACT_SUBTAXA(extract_input_ch)

    KRAKEN_EXTRACT_SUBTAXA.out.extracted_kraken2_reads
        .filter{ _meta, reads, _tid -> file(reads).size() > 0 }
        .map { meta, reads, tid -> [ meta + tid, tid, reads ] }.set { main_ch }

    // from this point onwards, meta is further differentiated by taxon id

    // 2. assemble into contigs and do reference selection
    MEGAHIT(main_ch)
    KMA_KMA(MEGAHIT.out.contigs.combine(kma_idx_ch))
    SELECT_BEST_KMA_REF(KMA_KMA.out.res, virus_db_ch.map {_meta, fasta -> fasta}).out.chosen_ref.set { chosen_ref_ch }

    // 3. create genome via iterative alignment/consensus calling
    // scaffold
    BWA_INDEX_REF(chosen_ref_ch)
    BWA_MEM_REF(MEGAHIT.out.contigs.join(BWA_INDEX_REF.out.index), "to_ref", true)
    CREATE_SCAFFOLD(BWA_MEM_REF.out.bam.join(chosen_ref_ch), 300)

    // intermediate
    BWA_INDEX_1(CREATE_SCAFFOLD.out.scaffold)
    BWA_MEM_1(main_ch.join(BWA_INDEX_1.out.index), "to_scaffold", true)
    IVAR_CONSENSUS_1(BWA_MEM_1.out.bam.join(CREATE_SCAFFOLD.out.scaffold), "inermediate", false)

    // final
    BWA_INDEX_2(IVAR_CONSENSUS_1.out.fasta)
    BWA_MEM_2(main_ch.join(BWA_INDEX_2.out.index), "to_first", true)
    IVAR_CONSENSUS_2(BWA_MEM_2.out.bam.join(IVAR_CONSENSUS_1.out.fasta), "final", false)

    emit: 
    fasta = IVAR_CONSENSUS_2.out.fasta
    classified_reads = main_ch

    }
