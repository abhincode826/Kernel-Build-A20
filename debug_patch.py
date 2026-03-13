with open('drivers/kernelsu/ksu.c', 'r') as f:
    c = f.read()

c = c.replace(
    'int __init kernelsu_init(void)\n{',
    '''int __init kernelsu_init(void)
{
\tstruct file *f;
\tf = filp_open("/data/local/tmp/ksu_init.txt", O_WRONLY|O_CREAT|O_TRUNC, 0644);
\tif (!IS_ERR(f)) {
\t\tkernel_write(f, "KSU_INIT_CALLED\\n", 16, 0);
\t\tfilp_close(f, NULL);
\t}'''
)

with open('drivers/kernelsu/ksu.c', 'w') as f:
    f.write(c)

print("Patch applied")
