#Requires -RunAsAdministrator
#$ErrorActionPreference = "Stop"

# ==============================================================================
# 基于 PolicyFileEditor 模块的标准去硬化脚本
# ==============================================================================


# 1. 确保网络剖面被纠正为 Private (规避 Public 防火墙丢包限制)
Write-Host "[1/6] Restoring Network Profile to Private..."
Get-NetConnectionProfile | ForEach-Object {
    Set-NetConnectionProfile -InterfaceIndex $_.InterfaceIndex -NetworkCategory Private -Confirm:$false -ErrorAction SilentlyContinue
}

# 2. 清理旧的 Listener 冲突
Write-Host "[2/6] Disposing conflicting listeners..."
& winrm.cmd delete winrm/config/listener?Address=*+Transport=HTTPS 2>$null


# 3. 精准调用 PolicyFileEditor 强修本地组策略物理文件
Write-Host "[3/6] Injecting GPO rules into Registry.pol..."
Import-Module PolicyFileEditor

$gpo_path   = "$env:SystemRoot\System32\GroupPolicy\Machine\Registry.pol"
$regService = "SOFTWARE\Policies\Microsoft\Windows\WinRM\Service"
$regClient  = "SOFTWARE\Policies\Microsoft\Windows\WinRM\Client"

# ★ 关键修复：AllowAutoConfig 控制 WinRM 是否真正绑定 HTTP 端口
Set-PolicyFileEntry -Path $gpo_path -Key $regService -ValueName "AllowAutoConfig"              -Data 1 -Type DWord

# 允许通过 WinRM 进行远程服务器管理
Set-PolicyFileEntry -Path $gpo_path -Key $regService -ValueName "AllowRemoteServiceManagement" -Data 1 -Type DWord

# 允许基本身份验证 -> 服务端与客户端双向启用
Set-PolicyFileEntry -Path $gpo_path -Key $regService -ValueName "AllowBasic"                   -Data 1 -Type DWord
Set-PolicyFileEntry -Path $gpo_path -Key $regClient  -ValueName "AllowBasic"                   -Data 1 -Type DWord

# 允许未加密通讯 -> 服务端与客户端双向启用
Set-PolicyFileEntry -Path $gpo_path -Key $regService -ValueName "AllowUnencryptedTraffic"      -Data 1 -Type DWord
Set-PolicyFileEntry -Path $gpo_path -Key $regClient  -ValueName "AllowUnencryptedTraffic"      -Data 1 -Type DWord


# 4. 强制让操作系统重载刚写入的策略，等待策略稳定落地
Write-Host "[4/6] Committing Group Policy changes via gpupdate..."
& gpupdate.exe /force /target:computer
Start-Sleep -Seconds 5


# 5. 系统开绿灯后，拉起 5985 的 Listener
Write-Host "[5/6] Initializing standard 5985 HTTP Listener..."
& winrm.cmd quickconfig -q

# 同步刷新本地服务端的运行时软件配置（双重保险）
& winrm.cmd set winrm/config/service '@{AllowUnencrypted="true"}'
& winrm.cmd set winrm/config/service/auth '@{Basic="true"}'


# 6. 配置物理防火墙，无条件跨网络剖面放行 5985 端口
Write-Host "[6/6] Hardening Firewall rule for port 5985..."
Remove-NetFirewallRule -Name "Ansible_WinRM_5985" -ErrorAction SilentlyContinue
New-NetFirewallRule -DisplayName "Ansible_WinRM_5985" -Name "Ansible_WinRM_5985" -Direction Inbound -Action Allow -Protocol TCP -LocalPort 5985 -Profile Any -Enabled True


# 安全重启 WinRM 服务刷新状态
Set-Service winrm -StartupType Automatic
Restart-Service winrm -Force


Write-Host ""
Write-Host "=============================================================================="
Write-Host "SUCCESS: WinRM unhardened cleanly! Current active listeners:"
Write-Host "=============================================================================="
& winrm.cmd enumerate winrm/config/listener

