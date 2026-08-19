process BAMTAX_NAMES {
    tag "${meta.id}"
    label "process_single"
    container "quay.io/epil02/bamtax:0.0.1"

    input:
    tuple val(meta), path(bam)

    output:
    tuple val(meta), path("*_contam_qnames.txt"), emit: qnames

    script:
    def prefix = task.ext.prefix ?: meta.id

    """
    bamtax names -i ${bam} -f 0.2 -a 0.2 -o ${prefix}_contam_qnames.txt
    """
}
