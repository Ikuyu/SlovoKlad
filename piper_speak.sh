#!/usr/bin/env bash
export PATH="$HOME/Library/Python/3.9/bin:$PATH"
MODEL_PATH="$(dirname "$0")/models/ru_RU-irina-medium.onnx"

# $1 = {text} (de uit te spreken tekst), $2 = {voice} (de stemnaam, genegeerd door Piper)
echo "$1" | piper --model "$MODEL_PATH" --output_file /tmp/piper_speech.wav > /dev/null 2>&1
afplay /tmp/piper_speech.wav
