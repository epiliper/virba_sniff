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

def get_species_tag_from_fasta(fasta) {
        file(fasta).withReader() {
                r -> def header = r.readLine() 
                return  header.split('>')[1]
            }
    }
// Denovo assembly for viruses

// Intakes 
// 1. reads presumably classified by kraken2 to belong to viruses
// 2. database of refs used to guide assembly
// 3. a list of taxonids to be used to attempt read extraction and assembly
workflow VIRUSES {
    take: 
    classified_reads        // tuple val(meta), path(extracted_reads), path(assignment), path(report), lineage-level reads
    taxon_virus_db          // path(virus fasta db)
    taxids                  // path(taxonid list)

    min_assembly_depth      // val
    min_assembly_coverage   // val 

    main:

    channel.value([[id: file(taxon_virus_db).baseName], taxon_virus_db]).set { virus_db_ch }
    KMA_INDEX(virus_db_ch)
    KMA_INDEX.out.index.map { _meta, idx -> idx }
    .set { kma_idx_ch }

    // 1)  attempt to generate FASTQs for each taxonid in our list 
    channel.fromPath(taxids)
        .splitCsv(sep: "\t", header: false, strip: true)
        .map { row -> [ id: row[0], name: row[1] ] }
        .dump(tag: "input taxonids")
        .set { tid_ch }

    classified_reads.combine(tid_ch).set { extract_input_ch }

    // TODO: eventually, we need to avoid multiple calls to the extract reads script, since I think we might risk re-extracting the same reads.
    KRAKEN_EXTRACT_SUBTAXA(extract_input_ch, false, true)

    KRAKEN_EXTRACT_SUBTAXA.out.extracted_kraken2_reads
    .join(KRAKEN_EXTRACT_SUBTAXA.out.num_ext_reads)
        // were we able to extract at least x reads for this taxon id?
        .filter{ _meta, _reads, _tid, num_reads -> num_reads.toInteger() >= 300 }
        // differentiate meta further by taxonid going forward
        .map { meta, reads, tid, _num_reads -> [ meta + [species: tid.name, taxon_id: tid.id], reads ] }
        .dump(tag: "subtaxa extraction output")
        .set { reads_ch }

    // 2) assemble into contigs and do reference selection
    MEGAHIT(reads_ch)
    KMA_KMA(MEGAHIT.out.contigs.combine(kma_idx_ch))

    // TODO: need to carry over ref tag into the meta, to avoid ivar creating the same file name for multi-reference (e.g. multi-segment) assemblies
    SELECT_BEST_KMA_REF(KMA_KMA.out.res, virus_db_ch.map {_meta, fasta -> fasta}, min_assembly_coverage, min_assembly_depth)
    SELECT_BEST_KMA_REF.out.chosen_ref
         // create a new job for each ref
        .flatMap{ meta, fastas -> fastas.collect { fasta -> tuple(meta, [tag: get_species_tag_from_fasta(fasta), file: fasta]) } }
        .dump(tag: "selected references")
        .set { chosen_ref_ch }

    // 3) create genome via iterative alignment/consensus calling


    // 3.1) scaffold
    /////////////////////////////////////////////////////////
    BWA_INDEX_REF(chosen_ref_ch.map { meta, refinfo -> [ meta, refinfo, refinfo.file ]})
    MEGAHIT.out.contigs.combine(BWA_INDEX_REF.out.index, by: 0)
        .dump(tag: "align round 1 input").set {aln_input1}

    BWA_MEM_REF(aln_input1, "to_ref", true)
    BWA_MEM_REF.out.bam.join(chosen_ref_ch, by: [0, 1])
        .dump(tag: "create scaffold input").set { scaffold_input }

    CREATE_SCAFFOLD(scaffold_input, 300)
    CREATE_SCAFFOLD.out.scaffold
        .dump(tag: "create scaffold output")
    /////////////////////////////////////////////////////////


    // 3.2) align to scaffold and make intermediate consensus
    /////////////////////////////////////////////////////////
    BWA_INDEX_1(CREATE_SCAFFOLD.out.scaffold)
    reads_ch.combine(BWA_INDEX_1.out.index, by: 0)
        .dump(tag: "align round 2 input").set {aln_input2}

    BWA_MEM_1(aln_input2, "to_scaffold", true)
    BWA_MEM_1.out.bam.join(CREATE_SCAFFOLD.out.scaffold, by: [0, 1])
        .dump(tag: "consensus 1 input").set {cons_input1}

    IVAR_CONSENSUS_1(cons_input1, "intermediate", false)
    IVAR_CONSENSUS_1.out.fasta.dump(tag: "consensus 1 output")
    /////////////////////////////////////////////////////////


    // 3.3) align to intermediate and make final consensus
    /////////////////////////////////////////////////////////
    BWA_INDEX_2(IVAR_CONSENSUS_1.out.fasta)
    reads_ch.combine(BWA_INDEX_2.out.index, by: 0)
        .dump(tag: "align round 3 input").set {aln_input3}

    BWA_MEM_2(aln_input3, "to_first", true)
    BWA_MEM_2.out.bam.join(IVAR_CONSENSUS_1.out.fasta, by: [0, 1])
        .dump(tag: "consensus 2 input").set {cons_input2}

    IVAR_CONSENSUS_2(cons_input2, "final", false)
    IVAR_CONSENSUS_2.out.fasta.dump(tag: "consensus 2 output")
    /////////////////////////////////////////////////////////

    emit: 
    fasta = IVAR_CONSENSUS_2.out.fasta
    classified_reads = reads_ch

    }
