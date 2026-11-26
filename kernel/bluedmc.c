// SPDX-License-Identifier: GPL-2.0
/* BluedMC status node: /sys/kernel/bluedmc/{version,features} (based on TechAmethyst) */
#include <linux/init.h>
#include <linux/kobject.h>
#include <linux/sysfs.h>

#define BLUEDMC_FEATURES "ksu susfs bbr ntfs3 wlblock tune tmpfs_xattr"

static ssize_t version_show(struct kobject *k, struct kobj_attribute *a, char *buf)
{
	return sysfs_emit(buf, "%s\n", "BluedMC v1.1");
}

static ssize_t features_show(struct kobject *k, struct kobj_attribute *a, char *buf)
{
	return sysfs_emit(buf, "%s\n", BLUEDMC_FEATURES);
}

static struct kobj_attribute ta_version_attr = __ATTR_RO(version);
static struct kobj_attribute ta_features_attr = __ATTR_RO(features);

static struct attribute *ta_attrs[] = {
	&ta_version_attr.attr,
	&ta_features_attr.attr,
	NULL,
};

static const struct attribute_group ta_group = {
	.attrs = ta_attrs,
};

static int __init bluedmc_init(void)
{
	struct kobject *kobj = kobject_create_and_add("bluedmc", kernel_kobj);

	if (!kobj)
		return -ENOMEM;
	return sysfs_create_group(kobj, &ta_group);
}
late_initcall(bluedmc_init);
