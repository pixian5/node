
file_path = "/Users/x/Library/Application Support/mihomo-party/profiles/node.txt"
with open(file_path, "r", encoding="utf-8") as f:
    lines = f.readlines()
# 删除空行
lines = [line for line in lines if line.strip()]
# 倒序排列
lines = lines[::-1]
# 第一行移动到最后一行
if lines:
    lines = lines[1:] + lines[:1]
with open(file_path, "w", encoding="utf-8") as f:
    f.writelines(lines)
