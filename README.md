1. Navigate to project root
1. Set your experiment settings in experiment-projects.xml (only modules and iteration count required, everything else is not implemented yet and does not affect execution)
1. Set openai key (`export OPENAI_API_KEY="[YOUR_KEY]"`)
1. `bash run_experiment.sh`, or `nohup bash run_experiment.sh &` to be able to close the terminal without interrupting the experiment
1. General logs can be found in the pynguin-runs folder; coverage and iteration specific logs can be found in the scratch folder
1. You can compress the results into a tar archive (`tar -czf experiment_data.tar.gz pynguin-runs scratch nohup.out`) and decompress it later (`tar -xzf experiment_data.tar.gz`)