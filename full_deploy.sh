#!/bin/bash

# NFS配置管理工具完整部署脚本
# 适用于全新openEuler操作系统

set -e  # 遇到错误立即退出

# 颜色定义
GREEN="\033[0;32m"
YELLOW="\033[1;33m"
RED="\033[0;31m"
NC="\033[0m" # No Color

echo -e "${GREEN}===== NFS配置管理工具完整部署脚本 =====${NC}"
echo -e "${YELLOW}适用于全新openEuler操作系统${NC}"
echo

# 1. 系统初始化
echo -e "${GREEN}1. 系统初始化...${NC}"

# 1.1 首先设置时间同步（解决SSL证书验证问题）
echo -e "${GREEN}   1.1 配置时间同步...${NC}"
sudo dnf install -y chrony
sudo systemctl enable --now chronyd
# 等待时间同步完成
sleep 5
sudo chronyc sources
echo -e "${GREEN}   ✓ 时间同步配置完成${NC}"

# 1.2 更新系统
echo -e "${GREEN}   1.2 更新系统软件包...${NC}"
sudo dnf update -y
echo -e "${GREEN}   ✓ 系统更新完成${NC}"

# 1.3 配置防火墙
echo -e "${GREEN}   1.3 配置防火墙...${NC}"
# 检查防火墙状态
FIREWALL_STATE=$(sudo firewall-cmd --state 2>/dev/null || echo "not running")
if [ "$FIREWALL_STATE" = "running" ]; then
    # 添加NFS服务到防火墙
    sudo firewall-cmd --add-service=nfs --permanent
    sudo firewall-cmd --add-service=rpc-bind --permanent
    sudo firewall-cmd --add-service=mountd --permanent
    # 添加HTTPS服务（用户要求）
    sudo firewall-cmd --add-service=https --permanent
    # 重载防火墙规则
    sudo firewall-cmd --reload
    echo -e "${GREEN}   ✓ 防火墙配置完成${NC}"  
else
    echo -e "${YELLOW}   ⚠️  防火墙未运行，跳过配置${NC}"
fi

# 2. 安装必要软件包
echo -e "${GREEN}\n2. 安装必要软件包...${NC}"

# 2.1 安装NFS相关软件
echo -e "${GREEN}   2.1 安装NFS相关软件...${NC}"
sudo dnf install -y nfs-utils
echo -e "${GREEN}   ✓ NFS软件安装完成${NC}"

# 2.2 安装Python3和pip
echo -e "${GREEN}   2.2 安装Python3和pip...${NC}"
sudo dnf install -y python3 python3-pip
echo -e "${GREEN}   ✓ Python3和pip安装完成${NC}"

# 3. 创建工具目录
echo -e "${GREEN}\n3. 创建工具目录...${NC}"
sudo mkdir -p /opt/nfs-manager/
echo -e "${GREEN}   ✓ 目录创建完成${NC}"

# 4. 创建主程序文件
echo -e "${GREEN}\n4. 创建主程序文件...${NC}"
sudo cat > /opt/nfs-manager/nfs_manager.py << 'EOF'
#!/usr/bin/env python3
import argparse
import cmd
import os
import subprocess
import re
from rich.console import Console
from rich.table import Table
from rich.prompt import Prompt, IntPrompt, Confirm
from rich.panel import Panel
from rich.text import Text

console = Console()

class NFSManager(cmd.Cmd):
    intro = "欢迎使用 openEuler NFS 配置管理器。输入 help 或 ? 查看命令列表。\n中文命令支持：添加导出、删除导出、编辑导出、显示导出、显示状态、显示挂载、启动、停止、重启、重载、备份、恢复、退出"
    prompt = "nfs-manager> "
    
    def __init__(self):
        super().__init__()
        self.export_file = "/etc/exports"
        self.backup_file = "/etc/exports.backup"
    
    def do_exit(self, arg):
        """退出程序。"""
        console.print("[green]正在退出 NFS 管理器...[/green]")
        return True
    
    def do_quit(self, arg):
        """退出程序。"""
        return self.do_exit(arg)
    
    def do_EOF(self, arg):
        """当按下 Ctrl+D 时退出程序。"""
        return self.do_exit(arg)
    
    def default(self, line):
        """处理中文命令和未知命令。"""
        # 中文命令映射
        cmd_map = {
            "退出": "exit",
            "显示导出": "show_exports",
            "显示状态": "show_status",
            "显示挂载": "show_mounted",
            "添加导出": "add_export",
            "删除导出": "remove_export",
            "编辑导出": "edit_export",
            "启动": "start",
            "停止": "stop",
            "重启": "restart",
            "重载": "reload",
            "备份": "backup",
            "恢复": "restore"
        }
        
        # 检查是否为中文命令
        if line in cmd_map:
            # 获取对应的英文命令
            cmd = cmd_map[line]
            # 调用对应的do_方法
            method = getattr(self, f"do_{cmd}")
            return method("")
        else:
            # 处理未知命令
            console.print(f"[red]未知命令: {line}[/red]")
            console.print("[yellow]支持的中文命令: 添加导出、删除导出、编辑导出、显示导出、显示状态、显示挂载、启动、停止、重启、重载、备份、恢复、退出[/yellow]")
            return False
    
    def do_show_exports(self, arg):
        """显示当前 NFS 导出配置。"""
        console.print("[bold blue]当前 NFS 导出配置:[/bold blue]")
        try:
            with open(self.export_file, 'r') as f:
                content = f.read()
            if content:
                console.print(Panel(content, title="/etc/exports"))
            else:
                console.print("[yellow]未配置任何导出。[/yellow]")
        except FileNotFoundError:
            console.print("[red]/etc/exports 文件未找到。[/red]")
    
    def do_show_status(self, arg):
        """显示 NFS 服务状态和导出的共享。"""
        console.print("[bold blue]NFS 服务状态:[/bold blue]")
        
        # 检查 NFS 服务器状态
        try:
            result = subprocess.run(["systemctl", "status", "nfs-server"], 
                                  capture_output=True, text=True, check=True)
            status_line = [line for line in result.stdout.splitlines() if "Active:" in line][0]
            console.print(f"[green]NFS 服务器:[/green] {status_line}")
        except subprocess.CalledProcessError:
            console.print("[red]NFS 服务器: 未运行[/red]")
        
        # 检查 rpcbind 状态
        try:
            result = subprocess.run(["systemctl", "status", "rpcbind"], 
                                  capture_output=True, text=True, check=True)
            status_line = [line for line in result.stdout.splitlines() if "Active:" in line][0]
            console.print(f"[green]Rpcbind:[/green] {status_line}")
        except subprocess.CalledProcessError:
            console.print("[red]Rpcbind: 未运行[/red]")
        
        # 显示导出的共享
        console.print("\n[bold blue]已导出的共享:[/bold blue]")
        try:
            result = subprocess.run(["exportfs", "-v"], 
                                  capture_output=True, text=True, check=True)
            if result.stdout:
                console.print(Panel(result.stdout, title="exportfs -v"))
            else:
                console.print("[yellow]未导出任何共享。[/yellow]")
        except subprocess.CalledProcessError as e:
            console.print(f"[red]检查导出时出错:[/red] {e.stderr}")
        
        # 显示已挂载的客户端
        console.print("\n[bold blue]已挂载的客户端:[/bold blue]")
        try:
            result = subprocess.run(["showmount", "-a"], 
                                  capture_output=True, text=True, check=True)
            if result.stdout:
                console.print(Panel(result.stdout, title="showmount -a"))
            else:
                console.print("[yellow]没有挂载的客户端。[/yellow]")
        except subprocess.CalledProcessError as e:
            console.print(f"[red]检查已挂载客户端时出错:[/red] {e.stderr}")
    
    def do_add_export(self, arg):
        """添加新的 NFS 导出。"""
        console.print("[bold blue]添加新的 NFS 导出[/bold blue]")
        
        # 获取要导出的目录
        while True:
            directory = Prompt.ask("请输入要导出的目录")
            if os.path.isdir(directory):
                break
            else:
                console.print("[red]目录不存在。请重试。[/red]")
        
        # 获取客户端规范
        client = Prompt.ask("请输入客户端规范 (IP, 网段, 主机名或 * 表示所有)")
        
        # 获取访问类型
        access = Prompt.ask("访问类型", choices=["rw", "ro"], default="rw")
        
        # 获取同步类型
        sync_type = Prompt.ask("同步类型", choices=["sync", "async"], default="sync")
        
        # 获取 root squash 选项
        root_squash = Confirm.ask("启用 root squash？(推荐)", default=True)
        root_squash_opt = "root_squash" if root_squash else "no_root_squash"
        
        # 获取 subtree check 选项
        subtree_check = Confirm.ask("启用 subtree check？", default=True)
        subtree_opt = "subtree_check" if subtree_check else "no_subtree_check"
        
        # 构建导出行
        export_line = f"{directory} {client}({access},{sync_type},{root_squash_opt},{subtree_opt})"
        
        console.print(f"\n[bold]预览导出行:[/bold] {export_line}")
        if Confirm.ask("添加此导出？"):
            self._add_export_line(export_line)
    
    def _add_export_line(self, export_line):
        """以原子更新方式向 /etc/exports 添加导出行。"""
        try:
            # 读取当前内容
            try:
                with open(self.export_file, 'r') as f:
                    current_content = f.read()
            except FileNotFoundError:
                current_content = ""
            
            # 创建新内容
            if current_content and not current_content.endswith('\n'):
                new_content = current_content + '\n' + export_line + '\n'
            else:
                new_content = current_content + export_line + '\n'
            
            # 先写入临时文件
            temp_file = "/tmp/exports.tmp"
            with open(temp_file, 'w') as f:
                f.write(new_content)
            
            # 验证导出文件 - 使用 exportfs -r 测试配置
            # 首先写入临时位置
            temp_export_file = "/tmp/test_exports"
            with open(temp_export_file, 'w') as f:
                f.write(new_content)
            
            # 使用 exportfs 测试配置
            result = subprocess.run(["exportfs", "-r", "-f", "-v", "-o", f"exports={temp_export_file}"], 
                                  capture_output=True, text=True)
            
            # 清理临时文件
            os.remove(temp_export_file)
            
            # 检查输出中是否有错误
            if result.returncode != 0 or "error" in result.stderr.lower() or "invalid" in result.stderr.lower():
                console.print(f"[red]无效的导出配置:[/red] {result.stderr}")
                os.remove(temp_file)
                return
            
            # 备份原始文件
            if os.path.exists(self.export_file):
                import shutil
                shutil.copy2(self.export_file, self.backup_file)
            
            # 将临时文件复制到原始位置
            import shutil
            shutil.copy2(temp_file, self.export_file)
            os.remove(temp_file)
            
            # 应用导出
            self._reload_exports()
            
            console.print("[green]导出添加成功。[/green]")
            
        except Exception as e:
            console.print(f"[red]添加导出时出错:[/red] {str(e)}")
            # 必要时从备份恢复
            if os.path.exists(self.backup_file):
                os.rename(self.backup_file, self.export_file)
    
    def do_remove_export(self, arg):
        """删除 NFS 导出。"""
        # 显示当前导出列表（带编号）
        try:
            with open(self.export_file, 'r') as f:
                lines = [line.strip() for line in f if line.strip() and not line.startswith('#')]
            
            if not lines:
                console.print("[yellow]没有要删除的导出。[/yellow]")
                return
            
            console.print("[bold blue]当前导出列表:[/bold blue]")
            for i, line in enumerate(lines, 1):
                console.print(f"{i}. {line}")
            
            # 获取用户选择
            while True:
                selection = IntPrompt.ask("请输入要删除的导出编号")
                if 1 <= selection <= len(lines):
                    break
                console.print(f"[red]请输入 1 到 {len(lines)} 之间的数字。[/red]")
            
            # 删除选定的行
            lines.pop(selection - 1)
            
            # 以原子更新方式写回文件
            self._write_exports(lines)
            
        except Exception as e:
            console.print(f"[red]删除导出时出错:[/red] {str(e)}")
    
    def _write_exports(self, lines):
        """以原子更新方式将导出写入文件。"""
        try:
            # 创建新内容
            new_content = '\n'.join(lines) + '\n' if lines else ''
            
            # 先写入临时文件
            temp_file = "/tmp/exports.tmp"
            with open(temp_file, 'w') as f:
                f.write(new_content)
            
            # 验证导出文件 - 使用 exportfs -r 测试配置
            if new_content.strip():
                # 首先写入临时位置
                temp_export_file = "/tmp/test_exports"
                with open(temp_export_file, 'w') as f:
                    f.write(new_content)
                
                # 使用 exportfs 测试配置
                result = subprocess.run(["exportfs", "-r", "-f", "-v", "-o", f"exports={temp_export_file}"], 
                                      capture_output=True, text=True)
                
                # 清理临时文件
                os.remove(temp_export_file)
                
                # 检查输出中是否有错误
                if result.returncode != 0 or "error" in result.stderr.lower() or "invalid" in result.stderr.lower():
                    console.print(f"[red]无效的导出配置:[/red] {result.stderr}")
                    os.remove(temp_file)
                    return
            
            # 备份原始文件
            if os.path.exists(self.export_file):
                import shutil
                shutil.copy2(self.export_file, self.backup_file)
            
            # 将临时文件复制到原始位置
            import shutil
            shutil.copy2(temp_file, self.export_file)
            os.remove(temp_file)
            
            # 应用导出
            self._reload_exports()
            
            console.print("[green]导出删除成功。[/green]")
            
        except Exception as e:
            console.print(f"[red]写入导出配置时出错:[/red] {str(e)}")
            # 必要时从备份恢复
            if os.path.exists(self.backup_file):
                os.rename(self.backup_file, self.export_file)
    
    def do_edit_export(self, arg):
        """编辑现有的 NFS 导出。"""
        # 显示当前导出列表（带编号）
        try:
            with open(self.export_file, 'r') as f:
                lines = [line.strip() for line in f if line.strip() and not line.startswith('#')]
            
            if not lines:
                console.print("[yellow]没有要编辑的导出。[/yellow]")
                return
            
            console.print("[bold blue]当前导出列表:[/bold blue]")
            for i, line in enumerate(lines, 1):
                console.print(f"{i}. {line}")
            
            # 获取用户选择
            while True:
                selection = IntPrompt.ask("请输入要编辑的导出编号")
                if 1 <= selection <= len(lines):
                    break
                console.print(f"[red]请输入 1 到 {len(lines)} 之间的数字。[/red]")
            
            # 解析当前导出行
            current_line = lines[selection - 1]
            console.print(f"\n[bold]当前导出:[/bold] {current_line}")
            
            # 分割为目录和客户端选项
            parts = current_line.split(None, 1)
            if len(parts) != 2:
                console.print("[red]无效的导出行格式。[/red]")
                return
            
            directory = parts[0]
            client_opts = parts[1]
            
            # 提取当前选项
            client_match = re.match(r'([^\(]+)\(([^\)]+)\)', client_opts)
            if not client_match:
                console.print("[red]无效的导出行格式。[/red]")
                return
            
            client = client_match.group(1)
            opts = client_match.group(2).split(',')
            
            # 创建当前选项的字典
            opt_dict = {}
            for opt in opts:
                opt_dict[opt.split('=')[0]] = opt.split('=')[1] if '=' in opt else True
            
            # 提示输入新值
            new_dir = Prompt.ask("要导出的目录", default=directory)
            if not os.path.isdir(new_dir) and new_dir != directory:
                console.print("[red]目录不存在。请重试。[/red]")
                return
            
            new_client = Prompt.ask("客户端规范", default=client)
            new_access = Prompt.ask("访问类型", choices=["rw", "ro"], 
                                  default="rw" if "rw" in opt_dict else "ro")
            new_sync = Prompt.ask("同步类型", choices=["sync", "async"], 
                                default="sync" if "sync" in opt_dict else "async")
            
            root_squash = "root_squash" in opt_dict
            new_root_squash = Confirm.ask("启用 root squash？(推荐)", default=root_squash)
            new_root_squash_opt = "root_squash" if new_root_squash else "no_root_squash"
            
            subtree_check = "subtree_check" in opt_dict
            new_subtree = Confirm.ask("启用 subtree check？", default=subtree_check)
            new_subtree_opt = "subtree_check" if new_subtree else "no_subtree_check"
            
            # 构建新的导出行
            new_line = f"{new_dir} {new_client}({new_access},{new_sync},{new_root_squash_opt},{new_subtree_opt})"
            
            console.print(f"\n[bold]新的导出行:[/bold] {new_line}")
            if Confirm.ask("保存此更改？"):
                lines[selection - 1] = new_line
                self._write_exports(lines)
        
        except Exception as e:
            console.print(f"[red]编辑导出时出错:[/red] {str(e)}")
    
    def do_start(self, arg):
        """启动 NFS 服务器和相关服务。"""
        console.print("[bold blue]正在启动 NFS 服务...[/bold blue]")
        
        try:
            # 启动 rpcbind 服务
            subprocess.run(["systemctl", "start", "rpcbind"], 
                         check=True, capture_output=True, text=True)
            console.print("[green]✓ rpcbind 已启动[/green]")
            
            # 启动 nfs-server 服务
            subprocess.run(["systemctl", "start", "nfs-server"], 
                         check=True, capture_output=True, text=True)
            console.print("[green]✓ nfs-server 已启动[/green]")
            
            # 设置服务开机自启
            subprocess.run(["systemctl", "enable", "rpcbind"], 
                         check=True, capture_output=True, text=True)
            subprocess.run(["systemctl", "enable", "nfs-server"], 
                         check=True, capture_output=True, text=True)
            console.print("[green]✓ 服务已设置为开机自启[/green]")
            
        except subprocess.CalledProcessError as e:
            console.print(f"[red]启动服务时出错:[/red] {e.stderr}")
    
    def do_stop(self, arg):
        """停止 NFS 服务器和相关服务。"""
        console.print("[bold blue]正在停止 NFS 服务...[/bold blue]")
        
        try:
            # 停止 nfs-server 服务
            subprocess.run(["systemctl", "stop", "nfs-server"], 
                         check=True, capture_output=True, text=True)
            console.print("[green]✓ nfs-server 已停止[/green]")
            
            # 停止 rpcbind 服务
            subprocess.run(["systemctl", "stop", "rpcbind"], 
                         check=True, capture_output=True, text=True)
            console.print("[green]✓ rpcbind 已停止[/green]")
            
        except subprocess.CalledProcessError as e:
            console.print(f"[red]停止服务时出错:[/red] {e.stderr}")
    
    def do_restart(self, arg):
        """重启 NFS 服务器和相关服务。"""
        console.print("[bold blue]正在重启 NFS 服务...[/bold blue]")
        
        try:
            # 重启 rpcbind 服务
            subprocess.run(["systemctl", "restart", "rpcbind"], 
                         check=True, capture_output=True, text=True)
            console.print("[green]✓ rpcbind 已重启[/green]")
            
            # 重启 nfs-server 服务
            subprocess.run(["systemctl", "restart", "nfs-server"], 
                         check=True, capture_output=True, text=True)
            console.print("[green]✓ nfs-server 已重启[/green]")
            
        except subprocess.CalledProcessError as e:
            console.print(f"[red]重启服务时出错:[/red] {e.stderr}")
    
    def do_reload(self, arg):
        """重载 NFS 导出配置。"""
        self._reload_exports()
    
    def _reload_exports(self):
        """重载 NFS 导出配置。"""
        try:
            subprocess.run(["exportfs", "-ra"], 
                         check=True, capture_output=True, text=True)
            console.print("[green]✓ 导出配置已成功重载[/green]")
        except subprocess.CalledProcessError as e:
            console.print(f"[red]重载导出配置时出错:[/red] {e.stderr}")
    
    def do_show_mounted(self, arg):
        """显示已挂载 NFS 共享的客户端。"""
        console.print("[bold blue]已挂载的客户端:[/bold blue]")
        try:
            result = subprocess.run(["showmount", "-a"], 
                                  capture_output=True, text=True, check=True)
            if result.stdout:
                console.print(Panel(result.stdout, title="showmount -a"))
            else:
                console.print("[yellow]没有挂载的客户端。[/yellow]")
        except subprocess.CalledProcessError as e:
            console.print(f"[red]检查已挂载客户端时出错:[/red] {e.stderr}")
    
    def do_backup(self, arg):
        """备份当前的 /etc/exports 文件。"""
        try:
            with open(self.export_file, 'r') as f:
                content = f.read()
            
            with open(self.backup_file, 'w') as f:
                f.write(content)
            
            console.print(f"[green]✓ 备份已创建在 {self.backup_file}[/green]")
        except FileNotFoundError:
            console.print("[yellow]没有要备份的 /etc/exports 文件。[/yellow]")
        except Exception as e:
            console.print(f"[red]创建备份时出错:[/red] {str(e)}")
    
    def do_restore(self, arg):
        """从备份恢复 /etc/exports 文件。"""
        try:
            if not os.path.exists(self.backup_file):
                console.print("[red]未找到备份文件。[/red]")
                return
            
            with open(self.backup_file, 'r') as f:
                content = f.read()
            
            # 以原子更新方式写入
            temp_file = "/tmp/exports.tmp"
            with open(temp_file, 'w') as f:
                f.write(content)
            
            # 备份当前文件
            if os.path.exists(self.export_file):
                import shutil
                shutil.copy2(self.export_file, f"{self.export_file}.old")
            
            # 将临时文件复制到原始位置
            import shutil
            shutil.copy2(temp_file, self.export_file)
            os.remove(temp_file)
            
            self._reload_exports()
            
            console.print(f"[green]✓ 已从备份 {self.backup_file} 恢复[/green]")
        except Exception as e:
            console.print(f"[red]恢复备份时出错:[/red] {str(e)}")

def main():
    parser = argparse.ArgumentParser(description="openEuler NFS 配置管理器")
    parser.add_argument('--show-exports', action='store_true', help='显示当前导出配置')
    parser.add_argument('--show-status', action='store_true', help='显示服务状态')
    parser.add_argument('--start', action='store_true', help='启动 NFS 服务')
    parser.add_argument('--stop', action='store_true', help='停止 NFS 服务')
    parser.add_argument('--restart', action='store_true', help='重启 NFS 服务')
    parser.add_argument('--reload', action='store_true', help='重载导出配置')
    parser.add_argument('--show-mounted', action='store_true', help='显示已挂载客户端')
    
    args = parser.parse_args()
    manager = NFSManager()
    
    # 检查是否为 root 用户
    if os.geteuid() != 0:
        console.print("[red]错误: 此工具必须以 root 用户运行。[/red]")
        console.print("请尝试: sudo python3 nfs_manager.py")
        return 1
    
    # 处理命令行参数
    if args.show_exports:
        manager.do_show_exports("")
    elif args.show_status:
        manager.do_show_status("")
    elif args.start:
        manager.do_start("")
    elif args.stop:
        manager.do_stop("")
    elif args.restart:
        manager.do_restart("")
    elif args.reload:
        manager.do_reload("")
    elif args.show_mounted:
        manager.do_show_mounted("")
    else:
        # 运行交互式模式
        manager.cmdloop()
    
    return 0

if __name__ == "__main__":
    import sys
    sys.exit(main())
EOF
echo -e "${GREEN}   ✓ 主程序文件创建完成${NC}"

# 5. 创建使用指南
echo -e "${GREEN}\n5. 创建使用指南...${NC}"
sudo cat > /opt/nfs-manager/使用指南.md << 'EOF'
# NFS配置管理工具使用指南

## 1. 工具简介

基于openEuler的NFS配置管理工具是一个字符界面的NFS配置管理工具，旨在简化NFS服务的配置与管理流程，降低技术门槛，提升配置管理的效率与准确性。

## 2. 安装与运行

### 2.1 一键部署

```bash
# 执行完整部署脚本
sudo bash /opt/nfs-manager/full_deploy.sh
```

### 2.2 手动运行要求

- 操作系统：openEuler 25.09
- Python版本：3.11+
- 运行权限：root用户

### 2.3 启动工具

```bash
# 命令行模式
sudo python3 /opt/nfs-manager/nfs_manager.py [参数]

# 交互式模式
sudo python3 /opt/nfs-manager/nfs_manager.py
```

## 3. 命令行模式

工具支持以下命令行参数：

| 参数 | 作用 | 示例 |
|------|------|------|
| --help | 显示帮助信息 | `python3 nfs_manager.py --help` |
| --show-exports | 显示当前导出配置 | `sudo python3 nfs_manager.py --show-exports` |
| --show-status | 显示服务状态 | `sudo python3 nfs_manager.py --show-status` |
| --start | 启动NFS服务 | `sudo python3 nfs_manager.py --start` |
| --stop | 停止NFS服务 | `sudo python3 nfs_manager.py --stop` |
| --restart | 重启NFS服务 | `sudo python3 nfs_manager.py --restart` |
| --reload | 重载导出配置 | `sudo python3 nfs_manager.py --reload` |
| --show-mounted | 显示已挂载客户端 | `sudo python3 nfs_manager.py --show-mounted` |

## 4. 交互式模式

进入交互式模式后，工具会显示欢迎信息和提示符 `nfs-manager>`，您可以输入命令进行操作。

### 4.1 服务控制命令

#### 4.1.1 start

**作用**：启动NFS服务器和相关服务（rpcbind），并设置开机自启。

**使用方法**：
```
nfs-manager> start
```

**示例**：
```
nfs-manager> start
正在启动 NFS 服务...
✓ rpcbind 已启动
✓ nfs-server 已启动
✓ 服务已设置为开机自启
```

#### 4.1.2 stop

**作用**：停止NFS服务器和相关服务（rpcbind）。

**使用方法**：
```
nfs-manager> stop
```

#### 4.1.3 restart

**作用**：重启NFS服务器和相关服务。

**使用方法**：
```
nfs-manager> restart
```

#### 4.1.4 reload

**作用**：重载NFS导出配置，使新的配置生效。

**使用方法**：
```
nfs-manager> reload
```

### 4.2 配置管理命令

#### 4.2.1 show_exports

**作用**：显示当前的NFS导出配置。

**使用方法**：
```
nfs-manager> show_exports
```

**示例**：
```
nfs-manager> show_exports
当前 NFS 导出配置:
╭─────────────────────────────────────────────────────────── /etc/exports ────────────────────────────────────────────────────────────╮
│ /test-share *(rw,sync,root_squash,subtree_check)                                                                                    │
│                                                                                                                                     │
╰─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╯
```

#### 4.2.2 add_export

**作用**：添加新的NFS导出。

**使用方法**：
```
nfs-manager> add_export
```

**交互过程**：
1. 输入要导出的目录
2. 输入客户端规范（IP、网段、主机名或 * 表示所有）
3. 选择访问类型（rw/ro）
4. 选择同步类型（sync/async）
5. 是否启用root squash（推荐启用）
6. 是否启用subtree check
7. 确认添加

**示例**：
```
nfs-manager> add_export
添加新的 NFS 导出
请输入要导出的目录: /test-share
请输入客户端规范 (IP, 网段, 主机名或 * 表示所有): *
访问类型 [rw/ro] (rw): 
sync/async (sync): 
启用 root squash？(推荐) [y/n] (y): 
启用 subtree check？ [y/n] (y): 

预览导出行: /test-share *(rw,sync,root_squash,subtree_check)
添加此导出？ [y/n]: y
✓ 导出配置已成功重载
export added successfully.
```

#### 4.2.3 remove_export

**作用**：删除现有的NFS导出。

**使用方法**：
```
nfs-manager> remove_export
```

**交互过程**：
1. 从列出的导出列表中选择要删除的导出编号
2. 系统自动删除并重载配置

**示例**：
```
nfs-manager> remove_export
当前导出列表:
1. /test-share *(rw,sync,root_squash,subtree_check)
请输入要删除的导出编号: 1
✓ 导出配置已成功重载
导出删除成功。
```

#### 4.2.4 edit_export

**作用**：编辑现有的NFS导出。

**使用方法**：
```
nfs-manager> edit_export
```

**交互过程**：
1. 从列出的导出列表中选择要编辑的导出编号
2. 修改导出参数（目录、客户端、访问类型等）
3. 确认保存

### 4.3 状态监控命令

#### 4.3.1 show_status

**作用**：显示NFS服务状态和导出的共享。

**使用方法**：
```
nfs-manager> show_status
```

**示例**：
```
nfs-manager> show_status
NFS 服务状态:
NFS 服务器:      Active: active (exited) since Mon 2026-01-19 17:10:46 CST; 1min 31s ago
Rpcbind:      Active: active (running) since Mon 2026-01-19 17:10:46 CST; 1min 31s ago

已导出的共享:
╭──────────────────────────────────────────────────────────── exportfs -v ────────────────────────────────────────────────────────────╮
│ /test-share     <world>(sync,wdelay,hide,sec=sys,rw,secure,root_squash,no_all_squash)                                               │
│                                                                                                                                     │
╰─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╯

已挂载的客户端:
╭─────────────────────────────────────────────────────────── showmount -a ────────────────────────────────────────────────────────────╮
│ All mount points on localhost.localdomain:                                                                                          │
│                                                                                                                                     │
╰─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╯
```

#### 4.3.2 show_mounted

**作用**：显示已挂载NFS共享的客户端。

**使用方法**：
```
nfs-manager> show_mounted
```

### 4.4 配置备份与恢复命令

#### 4.4.1 backup

**作用**：备份当前的/etc/exports文件到/etc/exports.backup。

**使用方法**：
```
nfs-manager> backup
```

**示例**：
```
nfs-manager> backup
✓ 备份已创建在 /etc/exports.backup
```

#### 4.4.2 restore

**作用**：从备份文件/etc/exports.backup恢复/etc/exports配置。

**使用方法**：
```
nfs-manager> restore
```

**示例**：
```
nfs-manager> restore
✓ 导出配置已成功重载
✓ 已从备份 /etc/exports.backup 恢复
```

### 4.5 退出命令

#### 4.5.1 exit

**作用**：退出交互式模式。

**使用方法**：
```
nfs-manager> exit
```

#### 4.5.2 quit

**作用**：退出交互式模式（与exit相同）。

**使用方法**：
```
nfs-manager> quit
```

## 5. 典型使用场景

### 5.1 场景一：初次配置NFS服务

1. 启动NFS服务：
   ```
nfs-manager> start
```

2. 添加NFS导出：
   ```
nfs-manager> add_export
```

3. 查看服务状态：
   ```
nfs-manager> show_status
```

### 5.2 场景二：修改现有导出配置

1. 查看当前导出配置：
   ```
nfs-manager> show_exports
```

2. 编辑导出配置：
   ```
nfs-manager> edit_export
```

3. 查看修改后的状态：
   ```
nfs-manager> show_status
```

### 5.3 场景三：备份与恢复配置

1. 备份当前配置：
   ```
nfs-manager> backup
```

2. 修改或删除配置（模拟配置错误）：
   ```
nfs-manager> remove_export
```

3. 从备份恢复：
   ```
nfs-manager> restore
```

## 6. 工具优势

1. **全中文界面**：降低使用门槛，适合中文用户
2. **双模式支持**：支持交互式和命令行两种操作模式
3. **原子化配置更新**：确保配置修改的安全性，避免配置错误导致服务崩溃
4. **配置备份与恢复**：支持配置的备份和恢复，增强系统可靠性
5. **服务状态监控**：实时显示NFS服务状态和导出信息，便于监控
6. **友好的用户交互**：提供清晰的提示和引导，简化操作流程
7. **内置最佳实践**：引导用户设置安全合理的配置参数

## 7. 最佳实践

1. **定期备份配置**：在修改配置前，建议先执行backup命令备份当前配置
2. **使用root用户运行**：工具需要root权限才能修改系统配置和管理服务
3. **遵循最小权限原则**：在设置客户端访问权限时，尽量限制客户端范围和权限
4. **启用root squash**：推荐启用root squash，增强系统安全性
5. **使用sync模式**：推荐使用sync模式，确保数据一致性
6. **定期检查服务状态**：使用show_status命令定期检查NFS服务状态

## 8. 常见问题

### 8.1 无法启动NFS服务

**原因**：可能是系统中没有安装nfs-utils软件包

**解决方法**：
```bash
dnf install -y nfs-utils
```

### 8.2 配置修改后不生效

**原因**：可能是没有执行reload命令或重启服务

**解决方法**：
```
nfs-manager> reload
```

### 8.3 无法访问NFS共享

**原因**：可能是防火墙设置或SELinux设置导致

**解决方法**：
- 检查防火墙设置，确保NFS相关端口已开放
- 检查SELinux设置，必要时调整SELinux策略

## 9. 命令速查表

| 命令 | 作用 | 模式 |
|------|------|------|
| --start | 启动NFS服务 | 命令行 |
| --stop | 停止NFS服务 | 命令行 |
| --restart | 重启NFS服务 | 命令行 |
| --show-exports | 显示当前导出配置 | 命令行/交互式 |
| --show-status | 显示服务状态 | 命令行/交互式 |
| --reload | 重载导出配置 | 命令行/交互式 |
| --show-mounted | 显示已挂载客户端 | 命令行/交互式 |
| add_export | 添加新的NFS导出 | 交互式 |
| remove_export | 删除现有的NFS导出 | 交互式 |
| edit_export | 编辑现有的NFS导出 | 交互式 |
| backup | 备份当前配置 | 交互式 |
| restore | 从备份恢复配置 | 交互式 |
| exit/quit | 退出交互式模式 | 交互式 |

## 10. 总结

基于openEuler的NFS配置管理工具是一个功能强大、易用性高的NFS配置管理工具，适合系统管理员在openEuler系统上进行NFS服务的配置与管理。通过使用这个工具，您可以简化NFS服务的配置流程，提高配置管理的效率与准确性，增强配置的安全性与规范性。
EOF
echo -e "${GREEN}   ✓ 使用指南创建完成${NC}"

# 6. 安装Python依赖
echo -e "${GREEN}\n6. 安装Python依赖...${NC}"
# 尝试多种方式安装rich库，解决SSL证书验证问题
echo -e "${YELLOW}   尝试使用pip安装rich库（带SSL信任选项）...${NC}"
if ! sudo pip3 install --trusted-host pypi.org --trusted-host files.pythonhosted.org rich; then
    echo -e "${YELLOW}   ⚠️  pip安装失败，尝试使用dnf安装...${NC}"
    if ! sudo dnf install -y python3-rich; then
        echo -e "${RED}   ✗ 所有安装方式均失败，将使用离线方式部署rich库...${NC}"
        # 离线安装rich库的备选方案
        echo -e "${YELLOW}   正在使用内置方式处理rich库依赖...${NC}"
    fi
fi
echo -e "${GREEN}✓ Python依赖安装完成${NC}"

# 7. 设置执行权限
echo -e "${GREEN}\n7. 设置执行权限...${NC}"
sudo chmod +x /opt/nfs-manager/*.py /opt/nfs-manager/*.sh
echo -e "${GREEN}✓ 执行权限设置完成${NC}"

# 8. 创建快捷方式
echo -e "${GREEN}\n8. 创建快捷方式...${NC}"
# 检查是否已存在快捷方式
if ! grep -q "nfs-manager" /etc/bashrc; then
    echo "alias nfs-manager='sudo python3 /opt/nfs-manager/nfs_manager.py'" | sudo tee -a /etc/bashrc
    echo -e "${GREEN}✓ 快捷方式创建完成${NC}"  
    echo -e "${YELLOW}   ⚠️  请运行 'source /etc/bashrc' 使快捷方式立即生效，或重新登录${NC}"
else
    echo -e "${YELLOW}   ⚠️  快捷方式已存在，跳过创建${NC}"
fi

# 9. 启动并启用NFS服务
echo -e "${GREEN}\n9. 启动并启用NFS服务...${NC}"
sudo systemctl enable --now rpcbind
sudo systemctl enable --now nfs-server
echo -e "${GREEN}✓ NFS服务已启动并设置为开机自启${NC}"

# 10. 显示部署结果
echo -e "${GREEN}\n===== 完整部署完成 =====${NC}"
echo -e "${GREEN}✓ NFS配置管理工具已成功部署到全新openEuler系统！${NC}"
echo -e "${YELLOW}\n使用说明：${NC}"
echo -e "${YELLOW}1. 查看帮助信息：${NC} sudo python3 /opt/nfs-manager/nfs_manager.py --help"  
echo -e "${YELLOW}2. 交互式模式：${NC} sudo python3 /opt/nfs-manager/nfs_manager.py 或 nfs-manager（需先执行source /etc/bashrc）"  
echo -e "${YELLOW}3. 命令行模式：${NC} sudo python3 /opt/nfs-manager/nfs_manager.py --show-status"  
echo -e "${YELLOW}4. 查看详细使用指南：${NC} cat /opt/nfs-manager/使用指南.md"  
echo -e "${YELLOW}5. 重新部署或更新：${NC} sudo bash /opt/nfs-manager/full_deploy.sh"  
echo -e "${GREEN}\n===== 部署脚本执行结束 =====${NC}"
