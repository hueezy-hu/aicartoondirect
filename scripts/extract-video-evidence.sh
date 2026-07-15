#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "用法: $0 <视频路径> <输出目录>" >&2
}

if [[ $# -ne 2 ]]; then
  usage
  exit 2
fi

video=$1
output_dir=$2

if [[ ! -f "$video" ]]; then
  echo "错误: 找不到视频文件: $video" >&2
  exit 3
fi

for command_name in ffprobe ffmpeg; do
  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "错误: 缺少必要命令: $command_name" >&2
    exit 4
  fi
done

sampled_dir="$output_dir/sampled"
scenes_dir="$output_dir/scenes"
sheets_dir="$output_dir/sheets"

mkdir -p "$sampled_dir" "$scenes_dir" "$sheets_dir"

ffprobe -v error \
  -show_entries format=duration:stream=index,codec_type,codec_name,width,height,r_frame_rate,avg_frame_rate,nb_frames \
  -of default=noprint_wrappers=1 \
  "$video" > "$output_dir/metadata.txt"

ffmpeg -hide_banner -loglevel error \
  -i "$video" \
  -vf "fps=1,scale=270:-1,drawtext=text='%{pts\\:hms}':x=8:y=8:fontsize=20:fontcolor=white:box=1:boxcolor=black@0.65" \
  -q:v 3 \
  "$sampled_dir/frame_%04d.jpg"

ffmpeg -hide_banner -loglevel info \
  -i "$video" \
  -vf "select='gt(scene,0.16)',showinfo,scale=360:-1" \
  -fps_mode vfr \
  -q:v 2 \
  "$scenes_dir/scene_%04d.jpg" \
  2> "$output_dir/scene-detection.log" || true

sed -n 's/.*pts_time:\([0-9.]*\).*/\1/p' \
  "$output_dir/scene-detection.log" > "$output_dir/scene-times.txt"

if command -v montage >/dev/null 2>&1; then
  shopt -s nullglob
  sampled_frames=("$sampled_dir"/*.jpg)
  if [[ ${#sampled_frames[@]} -gt 0 ]]; then
    montage "${sampled_frames[@]}" \
      -tile 5x4 \
      -geometry +4+4 \
      "$sheets_dir/contact-%02d.jpg"
  fi
fi

sampled_count=$(find "$sampled_dir" -maxdepth 1 -type f -name '*.jpg' | wc -l | tr -d ' ')
scene_count=$(find "$scenes_dir" -maxdepth 1 -type f -name '*.jpg' | wc -l | tr -d ' ')

{
  echo "video=$video"
  echo "sampled_frames=$sampled_count"
  echo "scene_candidates=$scene_count"
  if command -v montage >/dev/null 2>&1; then
    echo "contact_sheets=generated"
  else
    echo "contact_sheets=skipped (montage unavailable)"
  fi
} > "$output_dir/summary.txt"

echo "视频证据提取完成: $output_dir"
