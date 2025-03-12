#!/bin/bash

PID=$$
EXPERIMENT_NAME="experiment-projects"

function echo_blue {
  BLUE="\033[1;34m"
  NC="\033[0m"
  echo -e "${BLUE}${1}${NC}\n"
}

function sig_handler {
  echo "Killing ${0} including its children..."
  pkill -TERM -P "${PID}"
  echo -e "Terminated: ${0}\n"
}
trap sig_handler INT TERM HUP QUIT

function setup() {
  echo_blue "Create XML files for run..."
  python3.10 execution.py -d "${EXPERIMENT_NAME}.xml"

  chmod +x array_job.sh run_cluster_job.sh run-*.sh
}

function pre_run_cleanup() {
  rm -r targets/mistral
  rm -r slurm-logs
  rm -r outputs

  rm -r report-searchonly
  rm -r report-divllmthensearch
  rm -r report-llmthensearch

  #rm -r new-data
  rm -r scratch
  rm -r pynguin-runs
  #mkdir pynguin-runs

  post_run_cleanup
}

function post_run_cleanup() {
  echo_blue "Cleanup..."
  rm -rf array_job.sh run_cluster_job.sh
  find . -name "run-*.sh" -delete
  find . -name "slurm*.out" -delete
  echo_blue "Done"
}

function run() {
  echo_blue "Execute job on cluster..."
  ./run_cluster_job.sh
}

function merge() {
  echo_blue "Merge result CSVs to new-data/${EXPERIMENT_NAME}.csv"
  python3.10 merge_statistics_csv.py "${1}" "${2}"
}

function main {
  pre_run_cleanup
  setup
  run
  mkdir "new-data"
  merge "scratch/experiment-results" "new-data/${EXPERIMENT_NAME}.csv"
  post_run_cleanup
}

main
