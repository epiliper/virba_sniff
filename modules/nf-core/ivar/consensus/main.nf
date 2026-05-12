process IVAR_CONSENSUS {
    tag "$meta.id | $refinfo.tag"
    label 'process_medium'

    conda "${moduleDir}/environment.yml"
    container "${ workflow.containerEngine in ['singularity', 'apptainer'] && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/ivar:1.4.4--h077b44d_0' :
        'quay.io/biocontainers/ivar:1.4.4--h077b44d_0' }"

    input:
    tuple val(meta), val(refinfo), path(bam), path(fasta)
    val suffix
    val save_mpileup

    output:
    tuple val(meta), val(refinfo), path("*.fa")      , emit: fasta
    tuple val(meta), val(refinfo), path("*.qual.txt"), emit: qual
    tuple val(meta), val(refinfo), path("*.mpileup") , optional:true, emit: mpileup
    path "versions.yml"                , emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args = task.ext.args ?: ''
    def args2 = task.ext.args2 ?: ''
    def prefix = "${meta.id}_${refinfo.tag}"
    def mpileup = save_mpileup ? "| tee ${prefix}.mpileup" : ""

    """
    samtools \\
        mpileup \\
        --reference $fasta \\
        $args \\
        $bam \\
        $mpileup \\
        | ivar \\
            consensus \\
            $args2 \\
            -p ${prefix}_${suffix}

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        ivar: \$(ivar version | sed -n 's|iVar version \\(.*\\)|\\1|p')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    def touch_mpileup = save_mpileup ? "touch ${prefix}.mpileup" : ''
    """
    touch ${prefix}_${suffix}.fa
    touch ${prefix}_${suffix}.qual.txt
    $touch_mpileup

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        ivar: \$(ivar version | sed -n 's|iVar version \\(.*\\)|\\1|p')
    END_VERSIONS
    """
}
