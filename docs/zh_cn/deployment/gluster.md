---
title: 使用 GlusterFS 作为 JuiceFS 底层存储
sidebar_position: 8
---

## 本地环境

以下操作基于 ubuntu 2204 进行，kernel 版本为 5.15.0

### 安装 GlusterFS

```bash
apt update && apt install -y glusterfs-server
service glusterd start
```

## 配置 GlusterFS

```bash
mkdir -p /data/gv0
gluster volume create gv0 <your-ip>:/data/gv0 # append "force" to do local test
gluster volume start gv0
```

## 编译&运行 juicefs.gluster

```bash
git clone https://github.com/juicedata/juicefs
apt update && apt install golang libglusterfs-dev glusterfs-common uuid-dev
make juicefs.gluster
```

```bash
apt update && apt install redis-server && service redis-server start # 使用 redis 进行元数据存储
./juicefs.gluster format redis://localhost:6379/1 myjfs --storage gluster --bucket <your-ip>/gv0
./juicefs.gluster mount redis://localhost:6379/1 /mountpoint
```

到这里，基于 gluster 的 juicefs 就成功搭建好了。

## 生产环境

前文主要介绍了在自己本机上体验gluster的方法，生产环境中使用gluster肯定不能用根文件系统存储数据，而是需要专门配置的存储集群。

### [配置 Gluster 存储集群](https://docs.gluster.org/en/main/Quick-Start-Guide/Quickstart/)

- 存储集群中每台机器至少要有一个独立的数据盘
- 为保证性能，存储集群中每台机器规格最好一样，至少数据盘大小不要偏差太大

这里我们用4个节点组成 replica 2 集群进行演示。

1. 先在每个节点上安装好glusterfs
2. 格式化数据盘并挂载 brick
    ```bash
    mkfs.xfs -i size=512 /dev/sdb1
    mkdir -p /data/brick1
    echo '/dev/sdb1 /data/brick1 xfs defaults 1 2' >> /etc/fstab
    mount -a && mount
    ```
3. 从 node1 上： `gluster peer probe node2-ip && gluster peer probe node3-ip`
4. 检查 peer 状态：`gluster peer status`
5. 新建 GlusterFS 卷：
    ```bash
    gluster volume create gv0 replica 2 node1-ip:/brick1/gv0 node2-ip:/brick1/gv0 node3-ip:/brick1/gv0 node4-ip:/brick1/gv0
    ```
6. 启动 gv0 卷： `gluster volume start gv0`
7. `./juicefs.gluster format redis://redis-ip:6379/1 myjfs --storage gluster --bucket <any-node-ip>/gv0`

### 宕机恢复

主要参考 [gluster 官方文档](https://docs.gluster.org/en/main/Administrator-Guide/Managing-Volumes/).

当某一台存储节点损坏时，可以通过 `gluster volume replace-brick ... ` 命令，使用新节点替换坏掉的节点。

`gluster volume replace-brick gv0 old-node-ip:/brick1/gv0 new-node-ip:/brick1/gv0 commit force`
