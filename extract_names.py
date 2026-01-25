# 提取 node.txt 每行的 name 字段，并格式化输出为 - name_value
input_path = "node.txt"
output_path = "node_names.txt"

with open(input_path, "r", encoding="utf-8") as f:
    lines = f.readlines()

result = []
for line in lines:
    line = line.strip()
    if line.startswith("name:"):
        # 支持 name: "xxx" 或 name: 'xxx'
        parts = line.split(":", 1)
        if len(parts) == 2:
            name_value = parts[1].strip().strip('"').strip("'")
            result.append(f"- {name_value}")
    elif "name:" in line:
        # 支持 {name: "xxx", ...} 这种格式
        import re
        match = re.search(r'name:\s*["\"](.*?)["\"]', line)
        if match:
            result.append(f"- {match.group(1)}")

with open(output_path, "w", encoding="utf-8") as f:
    f.write("\n".join(result) + "\n")

print(f"已提取 {len(result)} 个 name，结果已保存到 {output_path}")
