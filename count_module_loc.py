# Script to count the lines of code in modules listed in experiment-projects.xml

import re
import xml.etree.ElementTree as ET
import os

def extract_modules_from_file(filepath):
    with open(filepath, 'r', encoding='utf-8') as f:
        content = f.read()
    # Pattern to match <module>...</module>
    pattern = r'<module>(.*?)</module>'
    modules = re.findall(pattern, content, re.DOTALL)
    return modules

def extract_sources_from_file(filepath):
    tree = ET.parse(filepath)
    root = tree.getroot()
    sources = [elem.text for elem in root.findall('.//sources')]
    return sources

def module_to_path(module_name, sources):
    # Try to find the module in any of the sources
    parts = module_name.split('.')
    rel_path = os.path.join(*parts) + '.py'
    for source in sources:
        candidate = os.path.join(source, rel_path)
        if os.path.isfile(candidate):
            return candidate
    # If not found, return the first possible path (for reporting)
    return os.path.join(sources[0], rel_path) if sources else rel_path

def count_loc(filepath):
    try:
        with open(filepath, 'r', encoding='utf-8') as f:
            lines = f.readlines()
        # Count non-empty, non-comment lines
        loc = sum(1 for line in lines if line.strip() and not line.strip().startswith('#'))
        return loc
    except FileNotFoundError:
        return None

# Example usage:
if __name__ == "__main__":
    xml_path = "experiment-projects.xml"  # Adjust path as needed
    modules = extract_modules_from_file(xml_path)
    sources = extract_sources_from_file(xml_path)
    total_loc = 0
    for module in modules:
        path = module_to_path(module, sources)
        loc = count_loc(path)
        if loc is not None:
            total_loc += loc
        print(f"{module}: {loc if loc is not None else 'File not found'}")
    print(f"Total LOC: {total_loc}")