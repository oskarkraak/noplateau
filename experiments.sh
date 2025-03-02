#!/bin/bash
#SBATCH --job-name=pynguin_tests
#SBATCH --array=0-2                 #
#SBATCH --nodes=1                    # Each job runs on a single node
#SBATCH --nodelist=gruenau1,gruenau2 # Use only these two nodes
#SBATCH --cpus-per-task=8            # 8 CPUs per experiment run
#SBATCH --mem=16G                    # 16 GB RAM per experiment run
#SBATCH --time=00:29:00              # 29 minutes per job
#SBATCH --output=slurm-logs/job_%A_%a.out
#SBATCH --error=slurm-logs/job_%A_%a.err

# Calculate experiment and run indices and set a unique seed
runs_per_experiment=1
experiment_index=$(( SLURM_ARRAY_TASK_ID / runs_per_experiment ))
run_index=$(( SLURM_ARRAY_TASK_ID % runs_per_experiment ))
seed=$((101 + SLURM_ARRAY_TASK_ID))

echo "pwd: $(eval pwd)"

export PYNGUIN_DANGER_AWARE=true
export PYTHONPATH=./src:$PYTHONPATH
mkdir targets/mistral

echo "Starting run $run_index of Experiment $((experiment_index+1)) on node $(hostname)"
echo "Using seed: $seed"

# Base parameters for the pynguin command
project_path="targets"
output_path="outputs"
verbose="--verbose"
assertions="--assertion_generation=NONE"
pynguin_cmd="python3.10 ./src/pynguin/__main__.py"
common_args="--output-path $output_path $verbose --seed $seed $assertions"

if [ $experiment_index -eq 0 ]; then
    echo "Running Experiment 1: Pynguin with 300s maximum search time"
    module_name="flutilspackages"
    report_dir="report-searchonly"
    max_time=300

    cmd="$pynguin_cmd --module-name $module_name $common_args --report-dir $report_dir --maximum_search_time $max_time --project-path \"$project_path\""
    echo "$cmd"
    eval "$cmd"

elif [ $experiment_index -eq 1 ]; then
    echo "Running Experiment 2: Preliminary mistral run then Pynguin with 270s maximum search time (NO diversity prompt)"
    module_name="mistral_out_${experiment_index}_${run_index}"

    project_path="targets/mistral"
    mistral_script="targets/mistral/$module_name.py"
    # Run the preliminary mistral script
    python3.10 ./src/pynguin/mistral.py --input targets/flutilspackages.py --output $mistral_script --diversity False
    # Trim the unnecessary markdown syntax from the output
    echo "Trimming markdown syntax from the generated file..."
    sed -i '1{/^\s*```python\s*$/d}; ${/^\s*```\s*$/d}' $mistral_script
    sed -i '/your_module/d' $mistral_script

    report_dir="report-llmthensearch"
    max_time=270
    initial_seeding="--initial-population-seeding True --initial_population_data targets"

    cmd="$pynguin_cmd --module-name $module_name $common_args $initial_seeding --report-dir $report_dir --maximum_search_time $max_time --project-path \"$project_path\""
    echo "$cmd"
    eval "$cmd"

elif [ $experiment_index -eq 2 ]; then
    echo "Running Experiment 3: Preliminary mistral run then Pynguin with 270s maximum search time (diversity prompt enabled)"
    module_name="mistral_out_${experiment_index}_${run_index}_div"

    project_path="targets/mistral"
    mistral_script="targets/mistral/$module_name.py"
    # Run the preliminary mistral script with diversity
    python3.10 ./src/pynguin/mistral.py --input targets/flutilspackages.py --output $mistral_script --diversity True
    # Trim the unnecessary markdown syntax from the output
    echo "Trimming markdown syntax from the generated file..."
    sed -i '1{/^\s*```python\s*$/d}; ${/^\s*```\s*$/d}' $mistral_script
    sed -i '/your_module/d' $mistral_script

    report_dir="report-divllmthensearch"
    max_time=270
    initial_seeding="--initial-population-seeding True --initial_population_data targets"

    cmd="$pynguin_cmd --module-name $module_name $common_args $initial_seeding --report-dir $report_dir --maximum_search_time $max_time --project-path $project_path"
    echo "$cmd"
    eval "$cmd"

else
    echo "Invalid experiment index: $experiment_index"
fi

echo "Experiment complete"

