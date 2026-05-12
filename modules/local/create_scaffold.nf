process CREATE_SCAFFOLD {
    tag "$meta.id | $refinfo.tag"
    label 'process_medium'
    container "quay.io/michellejlin/tpallidum_wgs:latest"

    // NOTE: bam is assumed to be sorted
    input:
    tuple val(meta), val(refinfo),  path(bam)
    val(min_contig_len)

    output:
    tuple val(meta), val(refinfo), path("*initial_consensus*.fasta"), emit: scaffold
    tuple val(meta), val(refinfo), path("*_contig_stats.tsv"), emit: contig_stats

    script:
    def prefix = "${meta.id}_${refinfo.tag}"

    """
    tp_make_seq.R $prefix $bam $refinfo.file $min_contig_len
    """
    }
