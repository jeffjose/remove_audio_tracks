#!/bin/bash

# Check if input file is provided
if [ $# -eq 0 ]; then
  echo "Usage: $0 <media_file>"
  exit 1
fi

input_file="$1"

# Check if file exists
if [ ! -f "$input_file" ]; then
  echo "Error: File '$input_file' does not exist"
  exit 1
fi

# Get audio track information
echo "Analyzing audio tracks in '$input_file'..."
echo "----------------------------------------"

# Get audio track information using ffprobe
ffprobe -v error -select_streams a -show_entries stream=index:stream_tags=language:stream_tags=title -of csv=p=0 "$input_file" | while IFS=, read -r index language title; do
  # Convert 1-based index to 0-based for ffmpeg
  zero_based_index=$((index - 1))
  echo "Track $index (ffmpeg index: $zero_based_index): Language = ${language:-unknown}, Title = ${title:-none}"
done

echo "----------------------------------------"
echo "Enter the track numbers you want to KEEP (space-separated)"
echo "For example: '1 3' to keep tracks 1 and 3 (shown above)"
read -p "Track numbers: " tracks_to_keep

# Exit if no tracks were specified
if [ -z "$tracks_to_keep" ]; then
  echo "No tracks specified. Exiting without making any changes."
  exit 0
fi

# Create output filename by inserting .fixed before the extension
output_file="${input_file%.*}.fixed.${input_file##*.}"

# Build the ffmpeg command
ffmpeg_cmd="ffmpeg -i \"$input_file\""

# First map video stream
ffmpeg_cmd="$ffmpeg_cmd -map 0:v"

# Add the selected audio tracks in order
audio_index=0
for track in $tracks_to_keep; do
  # Convert 1-based index to 0-based for ffmpeg
  zero_based_track=$((track - 1))
  ffmpeg_cmd="$ffmpeg_cmd -map 0:a:$zero_based_track?"
  audio_index=$((audio_index + 1))
done

# Map other streams
ffmpeg_cmd="$ffmpeg_cmd -map 0:s? -map 0:d? -map 0:t?"

# Complete the command
ffmpeg_cmd="$ffmpeg_cmd -c copy \"$output_file\""

echo "Executing: $ffmpeg_cmd"
eval "$ffmpeg_cmd"

if [ $? -eq 0 ]; then
  echo "Successfully created '$output_file'"
else
  echo "Error occurred while processing the file"
  exit 1
fi
