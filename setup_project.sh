#!/bin/bash

PROJECT_NAME=$1
PROJECT_PATH="./projects/$PROJECT_NAME"

echo "Setting up dependencies for project: $PROJECT_NAME"

# Install dependencies from setup.py without reinstalling the project
if [ -f "$PROJECT_PATH/setup.py" ]; then
  echo "Installing dependencies from setup.py..."
  python3.10 -m pip install --use-deprecated=legacy-resolver "$(python3.10 "$PROJECT_PATH/setup.py" egg_info --egg-base /tmp | grep 'install_requires' | cut -d'=' -f2 | tr -d '[],')"
fi

# Install dependencies from requirements.txt
if [ -f "$PROJECT_PATH/requirements.txt" ]; then
  echo "Installing dependencies from requirements.txt..."
  python3.10 -m pip install -r "$PROJECT_PATH/requirements.txt"
fi

# Install dependencies from pyproject.toml
if [ -f "$PROJECT_PATH/pyproject.toml" ]; then
  echo "Installing dependencies from pyproject.toml..."
  python3.10 -m pip install "$PROJECT_PATH"
fi

# Verify that dependencies are installed
python3.10 -m pip check || echo "Some dependencies may still be missing"

echo "Dependency setup complete for project: $PROJECT_NAME"
