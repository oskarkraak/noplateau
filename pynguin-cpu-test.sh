#!/bin/sh

#SBATCH --nodelist=gruenau1
#SBATCH --nodes=1-1
#SBATCH --ntasks=1
#SBATCH --mem-bind=local
#SBATCH --time=00:29:00
#SBATCH --job-name=pynguin
#SBATCH --cpus-per-task=1
#SBATCH --mem=4GB

if [ -z "$OPENAI_API_KEY" ]; then
    echo "Error: OPENAI_API_KEY environment variable is not set."
    exit 1
fi

base_dir=$(pwd)
INPUT_DIR="$base_dir/projects/python-string-utils/"
temp_dir="$base_dir/temp-experiment-${SLURM_JOB_ID}/"
OUTPUT_DIR="$temp_dir/output/"
PACKAGE_DIR="$temp_dir/package-dir/"

rm -rf $temp_dir
mkdir -p $temp_dir
mkdir -p $OUTPUT_DIR
mkdir -p $PACKAGE_DIR
touch $PACKAGE_DIR/package.txt
echo "python-string-utils==1.0.0" > "$PACKAGE_DIR/package.txt"

echo "Running on host: $(hostname)"
echo "SLURM node: $SLURMD_NODENAME"
echo "SLURM job running on: $SLURM_NODELIST"
echo "PATHS:"
echo "$base_dir"
echo "$INPUT_DIR"
echo "$OUTPUT_DIR"
echo "$PACKAGE_DIR"

apptainer run \
  --writable-tmpfs \
  --cleanenv \
  --contain \
  --bind "$INPUT_DIR:/input:ro" \
  --bind "$OUTPUT_DIR:/output" \
  --bind "$PACKAGE_DIR:/package:ro" \
  pynguin-container \
    "pynguin-cpu-test" \
    "python-string-utils" \
    "string_utils.manipulation" \
    "0" \
    "$OPENAI_API_KEY" \
    "/input" \
    "/output" \
    "0" \
    "false" \
    "false" \
    "true"
