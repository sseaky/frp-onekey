
About
-----------

Frp一键配置脚本，修改自 [clangcn](https://github.com/clangcn/onekey-install-shell) ，frp版本 0.34.2

- frp服务端、客户端一键安装，配置、删除
- 使用frp包自带的service管理启动服务
- 在ubuntu/debian上测试

## Usage

### Install

```Bash
wget https://raw.githubusercontent.com/seaky/frp-onekey/master/frp_manage.sh
sudo bash frp_manage.sh install {frps|frpc}
```
### Reconfig

```bash
sudo bash frp_manage.sh config {frps|frpc}
```

### Uninstall

```Bash
sudo bash frp_manage.sh uninstall
```

### Service

```bash
sudo systemctl {status|start|stop|restart} {frps|frpc}
```

### Reload

```bash
frpcc {status|reload}
```

## Example

### frps

![frps](img/frps.png)

### frpc

![frpc](img/frpc.png)



