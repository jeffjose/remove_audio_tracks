#!/bin/bash

check_fzf() {
  command -v fzf >/dev/null 2>&1
}

simple_fuzzy_search() {
  local dir="$1"
  local pattern="$2"
  
  echo "Searching for media files (no fzf found, using basic search)..."
  echo "Type part of the filename to filter, or press ENTER to see all:"
  read -r search_term
  
  echo ""
  echo "Select a file by number:"
  echo "------------------------"
  
  local files=()
  local i=1
  
  while IFS= read -r file; do
    if [[ -z "$search_term" ]] || [[ "${file,,}" == *"${search_term,,}"* ]]; then
      files+=("$file")
      echo "$i) $file"
      ((i++))
    fi
  done < <(find "$dir" -maxdepth 3 -type f \( -iname "*.mp4" -o -iname "*.mkv" -o -iname "*.avi" -o -iname "*.mov" -o -iname "*.webm" -o -iname "*.m4v" \) 2>/dev/null | sort)
  
  if [ ${#files[@]} -eq 0 ]; then
    echo "No matching media files found."
    return 1
  fi
  
  echo ""
  echo "Enter file number (or 'q' to quit): "
  read -r selection
  
  if [[ "$selection" == "q" ]]; then
    echo "Cancelled."
    exit 0
  fi
  
  if [[ "$selection" =~ ^[0-9]+$ ]] && [ "$selection" -ge 1 ] && [ "$selection" -le ${#files[@]} ]; then
    selected_file="${files[$((selection-1))]}"
    echo "$selected_file"
    return 0
  else
    echo "Invalid selection."
    return 1
  fi
}

fuzzy_search_with_fzf() {
  local dir="$1"
  
  local selected_file
  selected_file=$(find "$dir" -maxdepth 3 -type f \( -iname "*.mp4" -o -iname "*.mkv" -o -iname "*.avi" -o -iname "*.mov" -o -iname "*.webm" -o -iname "*.m4v" \) 2>/dev/null | \
    fzf --prompt="Select media file: " \
        --height=40% \
        --layout=reverse \
        --border \
        --preview='echo "File: {}" && echo "" && ffprobe -v error -select_streams a -show_entries stream=index,codec_name:stream_tags=language,title -of default=noprint_wrappers=1 {} 2>/dev/null | head -20' \
        --preview-window=right:50%:wrap)
  
  if [ -z "$selected_file" ]; then
    echo "No file selected."
    return 1
  fi
  
  echo "$selected_file"
  return 0
}

process_file() {
  local input_file="$1"
  local file_num="$2"
  local total_files="$3"
  
  if [ ! -f "$input_file" ]; then
    echo "Error: File '$input_file' does not exist"
    return 1
  fi
  
  # Show progress if processing multiple files
  if [ -n "$file_num" ] && [ -n "$total_files" ] && [ "$total_files" -gt 1 ]; then
    echo ""
    echo "================================================"
    echo "Processing file $file_num of $total_files"
    echo "================================================"
  fi
  
  echo "Analyzing audio tracks in '$input_file'..."
  echo "----------------------------------------"
  
  tracks=()
  track_indices=()
  
  while IFS=, read -r index language title; do
    track_indices+=("$index")
    display_num=$((${#tracks[@]} + 1))
    track_info="Language: ${language:-unknown}, Title: ${title:-none}"
    tracks+=("$track_info")
    echo "Track $display_num: $track_info"
  done < <(ffprobe -v error -select_streams a -show_entries stream=index:stream_tags=language:stream_tags=title -of csv=p=0 "$input_file")
  
  echo "----------------------------------------"
  
  if [ ${#tracks[@]} -eq 0 ]; then
    echo "No audio tracks found in the file."
    return 0
  fi
  
  selected=()
  for i in "${!tracks[@]}"; do
    selected[i]=true
  done
  
  display_menu() {
    clear
    local filename=$(basename "$input_file")
    
    # Show progress header if processing multiple files
    if [ -n "$file_num" ] && [ -n "$total_files" ] && [ "$total_files" -gt 1 ]; then
      echo "[$file_num/$total_files] Processing multiple files"
      echo ""
    fi
    
    echo "File: $filename"
    echo ""
    echo "Select audio tracks to KEEP:"
    echo "Use ↑/↓ to navigate, SPACE to toggle, ENTER to confirm, 'q' to quit"
    echo "================================================"
    
    for i in "${!tracks[@]}"; do
      if [ $i -eq $cursor ]; then
        if [ "${selected[$i]}" = true ]; then
          echo -e "\e[7m→ [✓] Track $((i+1)): ${tracks[$i]}\e[0m"
        else
          echo -e "\e[7m→ [ ] Track $((i+1)): ${tracks[$i]}\e[0m"
        fi
      else
        if [ "${selected[$i]}" = true ]; then
          echo "  [✓] Track $((i+1)): ${tracks[$i]}"
        else
          echo "  [ ] Track $((i+1)): ${tracks[$i]}"
        fi
      fi
    done
    
    echo "================================================"
  }
  
  cursor=0
  
  tput civis
  
  trap 'tput cnorm' INT TERM EXIT
  
  while true; do
    display_menu
    
    IFS= read -rsn1 key
    
    if [[ $key == $'\x1b' ]]; then
      read -rsn2 key
      case $key in
        '[A')
          ((cursor--))
          if [ $cursor -lt 0 ]; then
            cursor=$((${#tracks[@]} - 1))
          fi
          ;;
        '[B')
          ((cursor++))
          if [ $cursor -ge ${#tracks[@]} ]; then
            cursor=0
          fi
          ;;
      esac
    elif [[ $key == ' ' ]]; then
      if [ "${selected[$cursor]}" = true ]; then
        selected[$cursor]=false
      else
        selected[$cursor]=true
      fi
    elif [[ $key == '' ]]; then
      break
    elif [[ $key == 'q' ]] || [[ $key == 'Q' ]]; then
      tput cnorm
      clear
      echo "Cancelled. No changes made."
      return 0
    fi
  done
  
  tput cnorm
  clear
  
  tracks_to_keep=""
  echo "Selected tracks to keep:"
  echo "------------------------"
  for i in "${!tracks[@]}"; do
    if [ "${selected[$i]}" = true ]; then
      track_num=$((i+1))
      echo "Track $track_num: ${tracks[$i]}"
      tracks_to_keep="$tracks_to_keep $track_num"
    fi
  done
  
  if [ -z "$tracks_to_keep" ]; then
    echo ""
    echo "No tracks selected. Skipping file."
    return 0
  fi
  
  echo "------------------------"
  
  temp_file="${input_file%.*}.temp.${input_file##*.}"
  
  ffmpeg_cmd="ffmpeg -i \"$input_file\""
  
  ffmpeg_cmd="$ffmpeg_cmd -map 0:v"
  
  audio_index=0
  for track in $tracks_to_keep; do
    zero_based_track=$((track - 1))
    ffmpeg_cmd="$ffmpeg_cmd -map 0:a:$zero_based_track?"
    audio_index=$((audio_index + 1))
  done
  
  ffmpeg_cmd="$ffmpeg_cmd -map 0:s? -map 0:d? -map 0:t?"
  
  ffmpeg_cmd="$ffmpeg_cmd -c copy \"$temp_file\""
  
  echo "Executing: $ffmpeg_cmd"
  eval "$ffmpeg_cmd"
  
  if [ $? -eq 0 ]; then
    mv "$temp_file" "$input_file"
    echo "Successfully modified file."
    return 0
  else
    rm -f "$temp_file"
    echo "Error occurred while processing file."
    return 1
  fi
}

process_multiple_files() {
  local files=("$@")
  local total=${#files[@]}
  local current=1
  local successful=0
  local failed=0
  
  echo "Found $total media file(s) to process."
  
  for file in "${files[@]}"; do
    process_file "$file" "$current" "$total"
    if [ $? -eq 0 ]; then
      ((successful++))
    else
      ((failed++))
    fi
    ((current++))
  done
  
  echo ""
  echo "================================================"
  echo "Processing complete!"
  echo "Successfully processed: $successful file(s)"
  if [ $failed -gt 0 ]; then
    echo "Failed: $failed file(s)"
  fi
  echo "================================================"
}

main() {
  if [ $# -eq 0 ]; then
    echo "Usage: $0 <media_file_or_directory_or_pattern>"
    echo ""
    echo "Examples:"
    echo "  $0 video.mp4                  # Process a single file"
    echo "  $0 /path/to/videos            # Search and select from directory"
    echo "  $0 /path/to/*prefix*          # Process all matching files"
    echo "  $0 *.mp4                      # Process all mp4 files in current directory"
    echo "  $0 .                          # Search in current directory"
    exit 1
  fi
  
  # Check if we're dealing with a glob pattern by checking if multiple files match
  matching_files=()
  for arg in "$@"; do
    # If the argument contains wildcards and matches files
    if [[ "$arg" == *[\*\?]* ]]; then
      # Use nullglob to handle no matches gracefully
      shopt -s nullglob
      for file in $arg; do
        if [[ "$file" =~ \.(mp4|mkv|avi|mov|webm|m4v)$ ]]; then
          matching_files+=("$file")
        fi
      done
      shopt -u nullglob
    elif [ -f "$arg" ]; then
      # Single file argument
      matching_files+=("$arg")
    elif [ -d "$arg" ]; then
      # Directory argument - use fuzzy search
      input_path="$arg"
      echo "Directory mode: Searching for media files in '$input_path'"
      echo ""
      
      if check_fzf; then
        selected_file=$(fuzzy_search_with_fzf "$input_path")
      else
        selected_file=$(simple_fuzzy_search "$input_path")
      fi
      
      if [ $? -eq 0 ] && [ -n "$selected_file" ]; then
        echo ""
        echo "Selected: $selected_file"
        echo ""
        process_file "$selected_file" "" ""
      else
        echo "No file selected or error occurred."
        exit 1
      fi
      exit 0
    fi
  done
  
  # Process based on what we found
  if [ ${#matching_files[@]} -eq 0 ]; then
    echo "Error: No matching media files found for pattern '$1'"
    exit 1
  elif [ ${#matching_files[@]} -eq 1 ]; then
    # Single file - process directly
    process_file "${matching_files[0]}" "" ""
  else
    # Multiple files - process with progress counter
    process_multiple_files "${matching_files[@]}"
  fi
}

main "$@"