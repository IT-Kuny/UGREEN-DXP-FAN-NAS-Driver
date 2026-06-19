#include <linux/module.h>
#include <linux/export-internal.h>
#include <linux/compiler.h>

MODULE_INFO(name, KBUILD_MODNAME);

__visible struct module __this_module
__section(".gnu.linkonce.this_module") = {
	.name = KBUILD_MODNAME,
	.init = init_module,
#ifdef CONFIG_MODULE_UNLOAD
	.exit = cleanup_module,
#endif
	.arch = MODULE_ARCH_INIT,
};



static const struct modversion_info ____versions[]
__used __section("__versions") = {
	{ 0xbd069841, "kstrtoull" },
	{ 0xd272d446, "__stack_chk_fail" },
	{ 0xdd6830c7, "sysfs_emit" },
	{ 0x90a48d82, "__ubsan_handle_out_of_bounds" },
	{ 0xe4de56b4, "__ubsan_handle_load_invalid_value" },
	{ 0x31cf0efb, "__platform_driver_register" },
	{ 0x9c25c67b, "dmi_check_system" },
	{ 0x2044b429, "ioport_resource" },
	{ 0x52ebbba3, "__request_region" },
	{ 0x24db4285, "__release_region" },
	{ 0x4a37b312, "acpi_check_resource_conflict" },
	{ 0xa32db18a, "platform_device_alloc" },
	{ 0x92cd4f19, "platform_device_add_resources" },
	{ 0xd1389bc4, "platform_device_add_data" },
	{ 0x38114aec, "platform_device_add" },
	{ 0x23f25c0a, "__dynamic_pr_debug" },
	{ 0xa165a79a, "platform_device_put" },
	{ 0x1df5238a, "pv_ops" },
	{ 0xd272d446, "BUG_func" },
	{ 0x1f55c5b2, "kstrtoll" },
	{ 0xf46d5bf3, "mutex_lock" },
	{ 0xf46d5bf3, "mutex_unlock" },
	{ 0xf9c33b98, "__dynamic_dev_dbg" },
	{ 0x29f89088, "_dev_info" },
	{ 0x29f89088, "_dev_warn" },
	{ 0x31e61c69, "platform_get_resource" },
	{ 0x160d0b1a, "__devm_request_region" },
	{ 0x79190d7e, "devm_kmalloc" },
	{ 0xc1e6c71e, "__mutex_init" },
	{ 0x753da434, "devm_hwmon_device_register_with_groups" },
	{ 0x6462cbe7, "vid_which_vrm" },
	{ 0x29f89088, "_dev_err" },
	{ 0x058c185a, "jiffies" },
	{ 0xa7b2fea0, "vid_from_reg" },
	{ 0x2853920b, "param_ops_bool" },
	{ 0x2853920b, "param_array_ops" },
	{ 0x2853920b, "param_ops_ushort" },
	{ 0xd272d446, "__fentry__" },
	{ 0xd272d446, "__x86_return_thunk" },
	{ 0xe8213e80, "_printk" },
	{ 0xa165a79a, "platform_device_unregister" },
	{ 0xcf3c1742, "platform_driver_unregister" },
	{ 0x82fd7238, "__ubsan_handle_shift_out_of_bounds" },
	{ 0xbd03ed67, "__ref_stack_chk_guard" },
	{ 0xc7066f33, "module_layout" },
};

static const u32 ____version_ext_crcs[]
__used __section("__version_ext_crcs") = {
	0xbd069841,
	0xd272d446,
	0xdd6830c7,
	0x90a48d82,
	0xe4de56b4,
	0x31cf0efb,
	0x9c25c67b,
	0x2044b429,
	0x52ebbba3,
	0x24db4285,
	0x4a37b312,
	0xa32db18a,
	0x92cd4f19,
	0xd1389bc4,
	0x38114aec,
	0x23f25c0a,
	0xa165a79a,
	0x1df5238a,
	0xd272d446,
	0x1f55c5b2,
	0xf46d5bf3,
	0xf46d5bf3,
	0xf9c33b98,
	0x29f89088,
	0x29f89088,
	0x31e61c69,
	0x160d0b1a,
	0x79190d7e,
	0xc1e6c71e,
	0x753da434,
	0x6462cbe7,
	0x29f89088,
	0x058c185a,
	0xa7b2fea0,
	0x2853920b,
	0x2853920b,
	0x2853920b,
	0xd272d446,
	0xd272d446,
	0xe8213e80,
	0xa165a79a,
	0xcf3c1742,
	0x82fd7238,
	0xbd03ed67,
	0xc7066f33,
};
static const char ____version_ext_names[]
__used __section("__version_ext_names") =
	"kstrtoull\0"
	"__stack_chk_fail\0"
	"sysfs_emit\0"
	"__ubsan_handle_out_of_bounds\0"
	"__ubsan_handle_load_invalid_value\0"
	"__platform_driver_register\0"
	"dmi_check_system\0"
	"ioport_resource\0"
	"__request_region\0"
	"__release_region\0"
	"acpi_check_resource_conflict\0"
	"platform_device_alloc\0"
	"platform_device_add_resources\0"
	"platform_device_add_data\0"
	"platform_device_add\0"
	"__dynamic_pr_debug\0"
	"platform_device_put\0"
	"pv_ops\0"
	"BUG_func\0"
	"kstrtoll\0"
	"mutex_lock\0"
	"mutex_unlock\0"
	"__dynamic_dev_dbg\0"
	"_dev_info\0"
	"_dev_warn\0"
	"platform_get_resource\0"
	"__devm_request_region\0"
	"devm_kmalloc\0"
	"__mutex_init\0"
	"devm_hwmon_device_register_with_groups\0"
	"vid_which_vrm\0"
	"_dev_err\0"
	"jiffies\0"
	"vid_from_reg\0"
	"param_ops_bool\0"
	"param_array_ops\0"
	"param_ops_ushort\0"
	"__fentry__\0"
	"__x86_return_thunk\0"
	"_printk\0"
	"platform_device_unregister\0"
	"platform_driver_unregister\0"
	"__ubsan_handle_shift_out_of_bounds\0"
	"__ref_stack_chk_guard\0"
	"module_layout\0"
;

MODULE_INFO(depends, "hwmon-vid");

MODULE_ALIAS("dmi*:rvn*nVIDIA*:rn*FN68PT*:");

MODULE_INFO(srcversion, "E1946B67E2FFA84320566CB");
