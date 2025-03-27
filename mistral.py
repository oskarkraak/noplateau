import argparse
from gradio_client import Client
import datetime
import os
from openai import OpenAI

openai_api_key = os.getenv("OPENAI_API_KEY")
client = OpenAI(api_key=openai_api_key)

def main():
    parser = argparse.ArgumentParser(description="Gradio Client Script")
    parser.add_argument("--input", type=str, required=True, help="Path to input text file")
    parser.add_argument("--output", type=str, required=True, help="Path to output text file")
    parser.add_argument("--diversity", type=bool, required=True, help="Should the prompt promote test case diversity?")
    args = parser.parse_args()

    # Read input from file
    with open(args.input, "r", encoding="utf-8") as f:
        input_text = f.read().strip()

    if args.diversity:
        prompt = "You're an expert fuzzer and the most creative python test driven developer. You know that your team can write tests, but you are particularly good at writing unique tests. Write tests covering all edge cases and combinations that could break the following function under test:\n\n"
    else:
        prompt = "You're an expert python test driven developer. Write tests for the following function under test:\n\n"
    input_text = prompt + input_text
    input_text = input_text + "\n\n Respond only with the python code."

    result = mistral(input_text)

    # Write output to file
    with open(args.output, "w", encoding="utf-8") as f:
        f.write(result)

    print(f"Response saved to {args.output}")

def mistral(input_text: str) -> str:
    # Initialize Gradio Client
    client = Client("https://llm1-compute.cms.hu-berlin.de/")
    format = "%H:%M:%S"
    timestamp = datetime.datetime.now().strftime(format)
    print(f"[{timestamp}] Prompting...")
    result = client.predict(param_0=input_text, api_name="/chat")
    timestamp = datetime.datetime.now().strftime(format)
    print(f"[{timestamp}] Received Mistral response")
    return result

def chatgpt(input_text: str) -> str:
    # Initialize OpenAI API Client
    #os.getenv("OPENAI_API_KEY")
    format = "%H:%M:%S"
    timestamp = datetime.datetime.now().strftime(format)
    print(f"[{timestamp}] Prompting ChatGPT...")
    response = client.chat.completions.create(model="gpt-4o",
    messages=[
        {"role": "system", "content": "You are a helpful assistant."},
        {"role": "user", "content": input_text},
    ],
    max_tokens=1500,
    n=1,
    stop=None,
    temperature=0.7)
    result = response.choices[0].message.content.strip()
    timestamp = datetime.datetime.now().strftime(format)
    print(f"[{timestamp}] Received ChatGPT response")
    return result

if __name__ == "__main__":
    main()
