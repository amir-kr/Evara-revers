import subprocess
import os

def create_tunnel(name, tunnel_type, port, mode):
    """
    ایجاد تونل جدید با استفاده از rstun
    """
    try:
        # فرض می‌کنیم سرور روی localhost:9000 اجرا می‌شود
        server_addr = "127.0.0.1:9000"
        password = "123456"  # باید از تنظیمات امن دریافت شود
        mapping = f"{mode}^{port}^ANY"
        cmd = [
            "/usr/local/amir-tunnel/bin/rstunc",
            "--server-addr", server_addr,
            "--password", password,
            f"--{tunnel_type}-mappings", mapping
        ]
        result = subprocess.run(cmd, capture_output=True, text=True)
        if result.returncode == 0:
            return {'status': 'success', 'output': f'تونل {name} ایجاد شد.'}
        return {'status': 'error', 'output': result.stderr}
    except Exception as e:
        return {'status': 'error', 'output': str(e)}

def delete_tunnel(name):
    """
    حذف تونل (فرض می‌کنیم با توقف فرآیند انجام می‌شود)
    """
    try:
        # توقف فرآیند rstunc مربوط به تونل
        cmd = ["pkill", "-f", f"rstunc.*{name}"]
        result = subprocess.run(cmd, capture_output=True, text=True)
        if result.returncode == 0:
            return {'status': 'success', 'output': f'تونل {name} حذف شد.'}
        return {'status': 'error', 'output': result.stderr}
    except Exception as e:
        return {'status': 'error', 'output': str(e)}

def get_tunnel_status(name):
    """
    دریافت وضعیت تونل
    """
    try:
        # بررسی وضعیت فرآیند rstunc
        cmd = ["pgrep", "-f", f"rstunc.*{name}"]
        result = subprocess.run(cmd, capture_output=True, text=True)
        if result.returncode == 0:
            return "فعال"
        return "غیرفعال"
    except Exception as e:
        return str(e)
