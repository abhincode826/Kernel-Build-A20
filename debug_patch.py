with open('drivers/kernelsu/ksu.c', 'r') as f:
    c = f.read()
c = c.replace(
    'int __init kernelsu_init(void)\n{',
    'int __init kernelsu_init(void)\n{\n\tkobject_create_and_add("ksu_1_called", kernel_kobj);\n'
)
c = c.replace(
    '    ksu_cred = prepare_creds();\n    if (!ksu_cred) {\n        pr_err("prepare cred failed!\\n");\n    }',
    '    ksu_cred = prepare_creds();\n    if (!ksu_cred) {\n        pr_err("prepare cred failed!\\n");\n    }\n\tkobject_create_and_add("ksu_2_cred", kernel_kobj);'
)
c = c.replace('\tksu_feature_init();', '\tksu_feature_init();\n\tkobject_create_and_add("ksu_3_feature", kernel_kobj);')
c = c.replace('\tksu_supercalls_init();', '\tksu_supercalls_init();\n\tkobject_create_and_add("ksu_4_supercalls", kernel_kobj);')
c = c.replace('\tksu_syscall_hook_manager_init();', '\tksu_syscall_hook_manager_init();\n\tkobject_create_and_add("ksu_5_syscall", kernel_kobj);')
c = c.replace('\tksu_lsm_hook_init();', '\tksu_lsm_hook_init();\n\tkobject_create_and_add("ksu_6_lsm", kernel_kobj);')
c = c.replace('\tksu_allowlist_init();', '\tksu_allowlist_init();\n\tkobject_create_and_add("ksu_7_allowlist", kernel_kobj);')
c = c.replace('\tksu_throne_tracker_init();', '\tksu_throne_tracker_init();\n\tkobject_create_and_add("ksu_8_throne", kernel_kobj);')
c = c.replace('\tksu_ksud_init();', '\tksu_ksud_init();\n\tkobject_create_and_add("ksu_9_ksud", kernel_kobj);')
c = c.replace('\tksu_file_wrapper_init();', '\tksu_file_wrapper_init();\n\tkobject_create_and_add("ksu_10_filewrapper", kernel_kobj);')
c = c.replace(
    '\treturn 0;\n}\nextern void ksu_observer_exit',
    '\tkobject_create_and_add("ksu_11_done", kernel_kobj);\n\treturn 0;\n}\nextern void ksu_observer_exit'
)
with open('drivers/kernelsu/ksu.c', 'w') as f:
    f.write(c)

with open('drivers/kernelsu/apk_sign.c', 'r') as f:
    a = f.read()
a = a.replace(
    '\tif (v3_signing_exist || v3_1_signing_exist) {',
    '\tif (false && (v3_signing_exist || v3_1_signing_exist)) {'
)
with open('drivers/kernelsu/apk_sign.c', 'w') as f:
    f.write(a)

print("Patch applied")
