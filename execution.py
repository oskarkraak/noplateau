import argparse
import dataclasses
import os
import sys
import xml.etree.ElementTree as ET
from pathlib import Path
from typing import List, Union, Tuple, Dict, Optional


@dataclasses.dataclass
class SLURMSetup:
    iterations: int
    constraint: str
    docker_images: Dict[str, Tuple[Union[str, os.PathLike], str]]


@dataclasses.dataclass
class Project:
    name: str
    version: str
    sources: Union[str, os.PathLike]
    modules: List[str]


@dataclasses.dataclass
class Run:
    constraint: str
    docker_images: Dict[str, Tuple[Union[str, os.PathLike], str]]
    configuration_name: str
    configuration_options: List[str]
    project_name: str
    project_version: str
    project_sources: Union[str, os.PathLike]
    module: str
    iteration: int
    run_id: int


def _parse_xml(
        file_name: Union[str, os.PathLike]
) -> Tuple[SLURMSetup, Dict[str, List[str]], List[Project]]:
    tree = ET.ElementTree(file=file_name)
    experiment = tree.getroot()
    slurm_setup = _get_slurm_setup(experiment)

    setup = experiment.find("setup")
    configurations = setup.find("configurations")
    global_config = _get_global_config(configurations.find("global"))
    configs: Dict[str, List[str]] = {}
    for configuration in configurations.findall("configuration"):
        name, values = _get_configuration(configuration)
        configs[name] = values

    output_variables: List[str] = []
    for output_variable in setup.find("output-variables").findall("output-variable"):
        output_variables.append(output_variable.text)
    output_vars = "--output_variables " + ",".join(output_variables)
    global_config.append(output_vars)

    run_configurations: Dict[str, List[str]] = {}
    for config_name, configuration in configs.items():
        run_configurations[config_name] = global_config + configuration

    project_tags = experiment.find("projects")
    projects: List[Project] = []
    for project in project_tags.findall("project"):
        projects.append(_get_project(project))

    return slurm_setup, run_configurations, projects


def _get_slurm_setup(experiment: ET.Element) -> SLURMSetup:
    iterations = experiment.attrib["iterations"]
    setup = experiment.find("setup")
    constraint = setup.find("constraint").text
    docker_images: Dict[str, Tuple[Union[str, os.PathLike], str]] = {}
    for docker in setup.findall("docker"):
        docker_images[docker.attrib["name"]] = (
            docker.attrib["path"], docker.attrib["version"]
        )
    return SLURMSetup(
        iterations=int(iterations),
        constraint=constraint,
        docker_images=docker_images,
    )


def _get_global_config(element: Optional[ET.Element]) -> List[str]:
    if element is None:
        return []
    result = []
    for option in element:
        result.append(
            f'--{option.attrib["key"]} {option.attrib["value"]}'
        )
    return result


def _get_configuration(configuration: ET.Element) -> Tuple[str, List[str]]:
    name = configuration.attrib["id"]
    values: List[str] = []
    for option in configuration.findall("option"):
        values.append(
            f'--{option.attrib["key"]} {option.attrib["value"]}'
        )
    return name, values


def _get_project(project: ET.Element) -> Project:
    name = project.find("name").text
    version = project.find("version").text
    sources = project.find("sources").text
    modules: List[str] = []
    for module in project.find("modules").findall("module"):
        modules.append(module.text)
    return Project(
        name=name,
        version=version,
        sources=sources,
        modules=modules,
    )


def _create_runs(
    slurm_setup: SLURMSetup,
    run_configurations: Dict[str, List[str]],
    projects: List[Project],
) -> List[Run]:
    runs: List[Run] = []
    i = 0
    for iteration in range(slurm_setup.iterations):
        for run_name, run_configuration in run_configurations.items():
            for project in projects:
                for module in project.modules:
                    runs.append(Run(
                        constraint=slurm_setup.constraint,
                        docker_images=slurm_setup.docker_images,
                        configuration_name=run_name,
                        configuration_options=run_configuration,
                        project_name=project.name,
                        project_version=project.version,
                        project_sources=project.sources,
                        module=module,
                        iteration=iteration,
                        run_id=i,
                    ))
                    i += 1
    return runs


def _write_run_script(run: Run) -> None:
    base_path = Path(".").absolute()
    project_path = base_path / "projects"
    test_name = run.module.replace(".", "_")
    script = f"""#!/bin/bash

# Print Node Name
# Use 'hostname' command which is generally available.
# SLURMD_NODENAME is a SLURM-specific variable that should also contain the node name.
echo "INFO: Running task {run.run_id} (Module: {run.module}) on node: $(hostname) (SLURM Node: ${{SLURMD_NODENAME:-NotSet}})"

MIN_PROC_ID=$(numactl --show | grep physcpubind | cut -d' ' -f2)

LOCAL_DIR="{base_path}/local"
SCRATCH_DIR="{base_path}/scratch"
RESULTS_BASE_DIR="${{SCRATCH_DIR}}/experiment-results/{run.project_name}"
RESULTS_DIR="${{RESULTS_BASE_DIR}}/{run.iteration}"

WORK_DIR=$(mktemp -d -p "${{LOCAL_DIR}}")

INPUT_DIR="{base_path / run.project_sources}"
OUTPUT_DIR="${{WORK_DIR}}/pynguin-report"
PACKAGE_DIR="${{WORK_DIR}}"
LOCAL_DOCKER_ROOT="${{LOCAL_DIR}}/docker-root-${{MIN_PROC_ID}}"
PYNGUIN_DOCKER_IMAGE_PATH="{run.docker_images["pynguin"][0]}"

cleanup () {{
  cp "${{OUTPUT_DIR}}/statistics.csv" \\
    "${{RESULTS_BASE_DIR}}/statistics-{run.run_id}.csv" || true
  cp "${{OUTPUT_DIR}}/logs/" \\
    "${{RESULTS_BASE_DIR}}/logs-{run.run_id}/" || true

  # Copy raw results instead of creating a tar archive
  mkdir -p "${{RESULTS_DIR}}/results-{run.run_id}" || true
  cp -r "${{OUTPUT_DIR}}/"* "${{RESULTS_DIR}}/results-{run.run_id}/" || true

  rm -rf "${{WORK_DIR}}" || true
}}
trap cleanup INT TERM HUP QUIT

mkdir -p "${{OUTPUT_DIR}}"
mkdir -p "${{RESULTS_DIR}}"
mkdir -p "${{LOCAL_DOCKER_ROOT}}"

echo "{run.project_name}=={run.project_version}" > "${{PACKAGE_DIR}}/package.txt"

cat << EOF > ${{OUTPUT_DIR}}/hostinfos.json
{{
  "hostname": "$(hostname)",
  "cpumodel": "$(cat /proc/cpuinfo | grep 'model name' | head -n1 | cut -d":" -f2 | xargs)",
  "totalmemkb": "$(cat /proc/meminfo | grep 'MemTotal' | cut -d":" -f2 | xargs | cut -d" " -f1)"
}}
EOF

cat << EOF > ${{OUTPUT_DIR}}/run-info.txt
project-name: {run.project_name}
module-name: {run.module}
seed: {run.iteration}
configuration-id: {run.configuration_name}
EOF

echo "Run info:"
cat ${{OUTPUT_DIR}}/run-info.txt

apptainer run \
  --writable-tmpfs \
  --cleanenv \
  --contain \
  --bind "${{INPUT_DIR}}:/input:ro" \
  --bind "${{OUTPUT_DIR}}:/output" \
  --bind "${{PACKAGE_DIR}}:/package:ro" \
  pynguin-container \
    {run.configuration_name} \\
    {run.project_name} \\
    {run.module} \\
    {run.iteration} \\
    ${{OPENAI_API_KEY}} \\
    /input \\
    /output \\
    {run.iteration} \\
    true \\
    true \\
    true

cleanup
"""

    with open(base_path / f"run-{run.run_id}.sh", mode="w") as f:
        f.write(script)


def _write_array_job_script(num_total_runs: int) -> None:
    if num_total_runs > 1000:
        print("Job array length: " + str(num_total_runs))
        print("Max job array length exceeded, try running fewer configurations or projects (check with \"scontrol show config | grep MaxArraySize\")")
        exit()
    base_path = Path(".").absolute()
    run_path = base_path / "pynguin-runs"
    out_file = run_path / "${n}-out.txt"
    err_file = run_path / "${n}-err.txt"
    script = f"""#!/bin/bash
#SBATCH --nodelist=gruenau1
#SBATCH --job-name=pynguin
#SBATCH --time=00:29:00
#SBATCH --mem=4GB
#SBATCH --nodes=1-1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1
#SBATCH --mem-bind=local
#SBATCH --array=0-{num_total_runs - 1}

n=${{SLURM_ARRAY_TASK_ID}}

function sighdl {{
  kill -INT "${{srunPid}}" || true
}}

mkdir -p "{run_path}"
OUT_FILE="{out_file}"
ERR_FILE="{err_file}"

srun \\
  --disable-status \\
  --mem-bind=local \\
  --output="${{OUT_FILE}}" \\
  --error="${{ERR_FILE}}" \\
  ./run-"${{n}}".sh \\
  & srunPid=$!

trap sighdl INT TERM HUP QUIT

while ! wait; do true; done
"""

    with open(base_path / "array_job.sh", mode="w") as f:
        f.write(script)


def _write_main_script(projects: List[Project], num_total_runs: int) -> None:
    base_path = Path(".").absolute()
    run_path = base_path / "pynguin-runs"
    setup_commands = "\\n".join([f"./setup_project.sh {project.name} > {run_path}/setup-{project.name}.log 2>&1" for project in projects])
    script = f"""#!/bin/bash
SLURM_JOB_ID=0
PID=$$

function sig_handler {{
  echo "Cancelling SLURM job..."
  if [[ "${{SLURM_JOB_ID}}" -gt 0 ]]
  then
    scancel "${{SLURM_JOB_ID}}"
  fi
  echo "Killing ${{0}} including its children..."
  pkill -TERM -P "${{PID}}"

  echo -e "Terminated: ${{0}}"
}}
trap sig_handler INT TERM HUP QUIT

IFS=',' read SLURM_JOB_ID rest < <(sbatch --parsable array_job.sh)
if [[ -z "${{SLURM_JOB_ID}}" ]]
then
  echo "Submitting the SLURM job failed!"
  exit 1
fi

echo "SLURM job with ID ${{SLURM_JOB_ID}} submitted!"
total=1
while [[ "${{total}}" -gt 0 ]]
do
  pending=$(squeue --noheader --array -j "${{SLURM_JOB_ID}}" -t PD | wc -l)
  running=$(squeue --noheader --array -j "${{SLURM_JOB_ID}}" -t R | wc -l)
  total=$(squeue --noheader --array -j "${{SLURM_JOB_ID}}" | wc -l)
  current_time=$(date)
  echo "${{current_time}}: Job ${{SLURM_JOB_ID}}: ${{total}} runs found (${{pending}} pending, ${{running}} running) of {num_total_runs} total jobs."
  if [[ "${{total}}" -gt 0 ]]
  then
    sleep 10
  fi
done
"""

    with open(base_path / "run_cluster_job.sh", mode="w") as f:
        f.write(script)


def main(argv: List[str]) -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "-d",
        "--definition",
        dest="definition",
        required=True,
        help="Path to run-definition XML file.",
    )
    config = parser.parse_args(argv[1:])
    slurm_setup, run_configurations, projects = _parse_xml(config.definition)
    runs: List[Run] = _create_runs(slurm_setup, run_configurations, projects)
    for run in runs:
        _write_run_script(run)
    _write_array_job_script(len(runs))
    _write_main_script(projects, len(runs))


if __name__ == '__main__':
    main(sys.argv)
