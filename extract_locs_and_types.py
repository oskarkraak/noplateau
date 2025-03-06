#!/usr/bin/env python3
import csv
import dataclasses
import importlib
import inspect
import re
import subprocess
import sys
import typing
import xml.etree.ElementTree as ET
from pathlib import Path
from typing import Callable

REGEX = re.compile(r"Python\W+(\d+)\W+(\d+)\W+(\d+)\W+(\d+)", re.MULTILINE)
ROOT_PATH = Path(".").resolve()


def __execute_cloc(root_path: Path, sources: Path, module: str) -> int:
    module_path = Path(module.replace(".", "/") + ".py")
    module_path = root_path / sources / module_path

    proc = subprocess.Popen(
        ["cloc", str(module_path)],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    out, err = proc.communicate()
    lines = out.decode("UTF-8")
    matches = REGEX.search(lines)
    return int(matches.group(4))


def __extract_loc_data():
    tree = ET.ElementTree(file="emse.xml")
    root = tree.getroot()
    projects_tags = root.find("projects")
    with open(ROOT_PATH / "data" / "loc_data.csv", mode="w") as csv_file:
        field_names = ["name", "version", "module_name", "loc"]
        writer = csv.DictWriter(csv_file, fieldnames=field_names)
        writer.writeheader()
        for project in projects_tags:
            name = project.find("name").text
            version = project.find("version").text
            sources = Path(project.find("sources").text)
            for i, module in enumerate(project.find("modules").findall("module")):
                loc = __execute_cloc(ROOT_PATH, sources, module.text)
                writer.writerow({
                    "name": name,
                    "version": version,
                    "module_name": module.text,
                    "loc": loc,
                })


@dataclasses.dataclass
class ModuleTypes:
    parameter_types: set[type]
    return_types: set[type]


def __extract_types_for_module(project_path: Path, module_name: str) -> ModuleTypes:
    sys.path.insert(0, str(project_path))
    module_types = ModuleTypes(set(), set())
    try:
        module = importlib.import_module(module_name)
    except AttributeError:
        return ModuleTypes(set(), set())

    for key, member in inspect.getmembers(module):
        if (
            not inspect.isclass(member)
            and not inspect.isfunction(member)
        ):
            continue
        parameter_types, return_types = __infer_type_info(member)
        module_types.parameter_types.update(parameter_types)
        module_types.return_types.update(return_types)
    return module_types


def __infer_type_info(element: Callable) -> tuple[set[type], set[type]]:
    if inspect.isclass(element) and hasattr(element, "__init__"):
        return __infer(getattr(element, "__init__"))
    return __infer(element)


def __infer(element: Callable) -> tuple[set[type], set[type]]:
    parameter_types: set[type] = set()
    return_types: set[type] = set()
    signature = inspect.signature(element)
    try:
        hints = typing.get_type_hints(element)
    except BaseException:
        return parameter_types, return_types

    for param_name in signature.parameters:
        if param_name == "self":
            continue
        parameter_type = hints.get(param_name, None)
        if parameter_type is not None:
            parameter_types.add(parameter_type)
    return_type = hints.get("return", None)
    if return_type is not None:
        return_types.add(return_type)
    return parameter_types, return_types


def __extract_type_counts(run_definition_file: Path) -> None:
    tree = ET.ElementTree(file=run_definition_file)
    experiment = tree.getroot()
    projects_tag = experiment.find("projects")
    field_names = [
        "project_name",
        "num_parameter_types",
        "num_return_types",
        "parameter_types",
        "return_types",
    ]
    with open(ROOT_PATH / "data" / "types.csv", mode="w") as f:
        writer = csv.DictWriter(f, fieldnames=field_names, quoting=csv.QUOTE_ALL)
        writer.writeheader()
        for project in projects_tag.findall("project"):
            name = project.find("name").text
            sources = Path(project.find("sources").text)
            project_dir = ROOT_PATH / sources
            project_module_types = []
            for module in project.find("modules").findall("module"):
                module_name = module.text
                module_types = __extract_types_for_module(project_dir, module_name)
                project_module_types.append(module_types)
            parameter_types = set.union(
                *[m.parameter_types for m in project_module_types]
            )
            return_types = set.union(
                *[m.return_types for m in project_module_types]
            )
            writer.writerow({
                "project_name": name,
                "num_parameter_types": len(parameter_types),
                "num_return_types": len(return_types),
                "parameter_types": parameter_types,
                "return_types": return_types,
            })


def __extract_type_counts_per_module(run_definition_file: Path) -> None:
    tree = ET.ElementTree(file=run_definition_file)
    experiment = tree.getroot()
    projects_tag = experiment.find("projects")
    field_names = [
        "module_name",
        "num_parameter_types",
        "num_return_types",
        "parameter_types",
        "return_types",
    ]
    with open(ROOT_PATH / "data" / "types_per_project.csv", mode="w") as f:
        writer = csv.DictWriter(f, fieldnames=field_names, quoting=csv.QUOTE_ALL)
        writer.writeheader()
        for project in projects_tag.findall("project"):
            sources = Path(project.find("sources").text)
            project_dir = ROOT_PATH / sources
            for module in project.find("modules").findall("module"):
                module_name = module.text
                module_types = __extract_types_for_module(project_dir, module_name)
                writer.writerow({
                    "module_name": module_name,
                    "num_parameter_types": len(module_types.parameter_types),
                    "num_return_types": len(module_types.return_types),
                    "parameter_types": module_types.parameter_types,
                    "return_types": module_types.return_types,
                })


if __name__ == '__main__':
    __extract_loc_data()
    rdf = Path(".").resolve() / "emse.xml"
    __extract_type_counts(rdf)
    __extract_type_counts_per_module(rdf)
