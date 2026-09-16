import subprocess
from pathlib import Path

# =========================
# 需要修改的参数
# =========================

input_video = r"D:\the inner darkness\bro you dont wanna enter this\are you sure about that？\还原视频\db886a68d6365691704b600d5f6f03fe.mp4"

# 从哪里开始截
start_time = "00:10:00"

# 截取多少秒
duration = 8

# =========================
# 输出文件
# =========================

input_path = Path(input_video)

output_path = input_path.with_name(
    f"{input_path.stem}_test_{start_time.replace(':', '-')}_{duration}s.mp4"
)

# =========================
# FFmpeg
# =========================

cmd = [
    "ffmpeg",
    "-y",

    # 精确定位
    "-ss", start_time,

    "-i", str(input_path),

    # 截取时长
    "-t", str(duration),

    # 视频：标准 H.264
    "-c:v", "libx264",

    # 高质量，避免测试片段本身损失太大
    "-crf", "16",

    # 因为只是几秒测试片段，优先速度
    "-preset", "fast",

    # 最通用的 MP4 像素格式
    "-pix_fmt", "yuv420p",

    # 音频：标准 AAC
    "-c:a", "aac",
    "-b:a", "192k",

    # 把 MP4 的 moov atom 放到文件头部
    # 提高播放器兼容性
    "-movflags", "+faststart",

    str(output_path)
]

print("开始截取...")
print(f"输入：{input_path}")
print(f"输出：{output_path}")
print(f"起始：{start_time}")
print(f"长度：{duration} 秒")

subprocess.run(cmd, check=True)

print("\n完成。")
print(f"文件位置：{output_path}")