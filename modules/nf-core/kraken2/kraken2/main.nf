process KRAKEN2_KRAKEN2 {
    tag "$meta.id"
    label 'process_high'

    conda "${moduleDir}/environment.yml"
    container "${ workflow.containerEngine in ['singularity', 'apptainer'] && !task.ext.singularity_pull_docker_container ?
        'https://community-cr-prod.seqera.io/docker/registry/v2/blobs/sha256/0f/0f827dcea51be6b5c32255167caa2dfb65607caecdc8b067abd6b71c267e2e82/data' :
        'community.wave.seqera.io/library/kraken2_coreutils_pigz:920ecc6b96e2ba71' }"

    input:
    tuple val(meta), path(reads)
    path  dbs
    val save_output_fastqs
    val save_reads_assignment


    output:
    tuple val(meta), path('k2out/*.classified{.,_}*')     , optional:true, emit: classified_reads_fastq
    tuple val(meta), path('k2out/*.unclassified{.,_}*')   , optional:true, emit: unclassified_reads_fastq
    tuple val(meta), path('k2out/*classifiedreads.txt')   , optional:true, emit: classified_reads_assignment
    tuple val(meta), path('k2out/*report.txt')                           , emit: report
    tuple val("${task.process}"), val('kraken2'), eval('kraken2 --version 2>&1 | head -1 | sed "s/^.*Kraken version //; s/ .*//"'), topic: versions, emit: versions_kraken2
    tuple val("${task.process}"), val('pigz'), eval('pigz --version 2>&1 | sed "s/pigz //g"'), topic: versions, emit: versions_pigz

    when:
    task.ext.when == null || task.ext.when

    script:
    def db_arg = dbs.join(",")
    def prefix = task.ext.prefix ?: "${meta.id}"
    def outprefix = "k2out/${prefix}"
    def args = task.ext.args ?: ''
    def paired       = meta.single_end ? "" : "--paired"
    def classified   = meta.single_end ? "${outprefix}.classified.fastq"   : "${outprefix}.classified#.fastq"
    def unclassified = meta.single_end ? "${outprefix}.unclassified.fastq" : "${outprefix}.unclassified#.fastq"
    def classified_option = "--classified-out ${classified}"
    def unclassified_option = "--unclassified-out ${unclassified}"
    def readclassification_option = "--output ${outprefix}.kraken2.classifiedreads.txt"
    def compress_reads_command = "pigz -p $task.cpus k2out/*.fastq"

    """
    mkdir -p k2out
    kraken2 \\
        --db $db_arg \\
        --threads $task.cpus \\
        --report ${outprefix}.kraken2.report.txt \\
        --gzip-compressed \\
        ${unclassified_option} \\
        ${classified_option} \\
        ${readclassification_option} \\
        $paired \\
        $args \\
        $reads

    $compress_reads_command
    """
}
