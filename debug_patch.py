with open('drivers/kernelsu/ksu.c', 'r') as f:
    c = f.read()

c = c.replace(
    'int __init kernelsu_init(void)\n{',
    'int __init kernelsu_init(void)\n{\n\tpr_info("KSU: INIT START\\n");'
)
c = c.replace(
    '\treturn 0;\n}',
    '\tpr_info("KSU: INIT END\\n");\n\treturn 0;\n}'
)

with open('drivers/kernelsu/ksu.c', 'w') as f:
    f.write(c)

print("Patch applied")
