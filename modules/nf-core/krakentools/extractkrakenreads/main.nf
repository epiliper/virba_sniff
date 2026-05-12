process KRAKENTOOLS_EXTRACTKRAKENREADS {

    tag "$meta.id"
    label 'process_medium'

    conda "${moduleDir}/environment.yml"
    container "${workflow.containerEngine in ['singularity', 'apptainer'] && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/krakentools:1.2.1--pyh7e72e81_0':
        'quay.io/biocontainers/krakentools:1.2.1--pyh7e72e81_0'}"

    input:
    tuple val(meta), path(classified_reads_assignment), path(classified_reads_fastq), path(report), val(taxinfo)
    val include_parents
    val include_children

    output:
    tuple val(meta), path("*.{fastq.gz,fasta.gz}"), val(taxinfo), emit: extracted_kraken2_reads
    tuple val(meta), env('NUM_EXTRACTED_READS'), emit: num_ext_reads

    path "versions.yml", emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args = task.ext.args ?: ''
    def prefix = "${meta.id}_${taxinfo.name}"
    def extension = args.contains("--fastq-output") ? "fastq" : "fasta"
    def input_reads_command = meta.single_end ? "-s $classified_reads_fastq" : "-s1 ${classified_reads_fastq[0]} -s2 ${classified_reads_fastq[1]}"
    def output_reads_command = meta.single_end ? "-o ${prefix}.extracted_kraken2_read.${extension}" : "-o ${prefix}.extracted_kraken2_read_1.${extension} -o2 ${prefix}.extracted_kraken2_read_2.${extension}"
    def gzip_reads_command = meta.single_end ? "gzip ${prefix}.extracted_kraken2_read.${extension}" : "gzip ${prefix}.extracted_kraken2_read_1.${extension}; gzip ${prefix}.extracted_kraken2_read_2.${extension}"
    def report_option = report ? "-r ${report}" : ""
    def VERSION = '1.2.1' // WARN: Version information not provided by tool on CLI. Please update this string when bumping container versions.
    def parents = include_parents ? "--include-parents" : ""
    def children = include_children ? "--include-children" : ""

    def readcount_cmd = """
    sum=0
    for file in ${prefix}*extracted_kraken2*${extension}.gz; do
        nlines=\$(zcat \$file | wc -l)
        nreads=\$((nlines / 4))
        echo "\$file has \$nreads reads..."
        sum=\$((sum + nreads))
    done

    export NUM_EXTRACTED_READS=\$sum
    """

    """
    extract_kraken_reads.py \\
        ${args} \\
        -t ${taxinfo.id}\\
        -k $classified_reads_assignment \\
        $report_option \\
        $input_reads_command \\
        $output_reads_command \\
        $children \\
        $parents

    $gzip_reads_command
    $readcount_cmd

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        extract_kraken_reads.py: ${VERSION}
    END_VERSIONS
    """
    stub:
    def args = task.ext.args ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    def extension = args.contains("--fastq-output") ? "fastq" : "fasta"
    def gzip_reads_command = meta.single_end ?
        "gzip ${prefix}.extracted_kraken2_read.${extension}" :
        "gzip ${prefix}.extracted_kraken2_read_1.${extension}; gzip ${prefix}.extracted_kraken2_read_2.${extension}"
    def VERSION = '1.2.1' // WARN: Version information not provided by tool on CLI. Please update this string when bumping container versions.

    """
    if [ "$meta.single_end" == "true" ];
    then
        touch ${prefix}.extracted_kraken2_read.${extension}
        $gzip_reads_command
    else
        touch ${prefix}.extracted_kraken2_read_1.${extension}
        touch ${prefix}.extracted_kraken2_read_2.${extension}
        $gzip_reads_command
    fi

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        extract_kraken_reads.py: ${VERSION}
    END_VERSIONS
    """
}
