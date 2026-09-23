#!/usr/bin/env python3
from pathlib import Path
import re

ROOT = Path("pmbootstrap/pmb")

def patch_file(path: Path, transform, label: str):
    text = path.read_text()
    new = transform(text)
    if new != text:
        path.write_text(new)
        print(f"✓ Patched {path}: {label}")
        return True
    print(f"- No change {path}: {label}")
    return False

# 1) Asegurar que el chroot nativo instale losetup completo
config_init = ROOT / "config" / "__init__.py"
if config_init.exists():
    def add_losetup_to_native_packages(text: str) -> str:
        if '"losetup"' in text or "'losetup'" in text:
            return text

        # Caso típico: lista con util-linux, parted, cryptsetup, qemu-...
        text = text.replace('"util-linux",', '"util-linux",\n "losetup",')
        text = text.replace("'util-linux',", "'util-linux',\n 'losetup',")
        return text

    patch_file(config_init, add_losetup_to_native_packages, "add losetup to native packages")

# 2) Parche fuerte: todo losetup interno debe apuntar a /usr/sbin/losetup
losetup_py = ROOT / "install" / "losetup.py"
if losetup_py.exists():
    def force_usr_sbin_losetup(text: str) -> str:
        # Deshacer parche anterior incorrecto a /sbin/losetup
        text = text.replace('"/sbin/losetup"', '"/usr/sbin/losetup"')
        text = text.replace("'/sbin/losetup'", "'/usr/sbin/losetup'")

        # Convertir llamadas directas ["losetup", ...] a ["/usr/sbin/losetup", ...]
        text = text.replace('["losetup"', '["/usr/sbin/losetup"')
        text = text.replace("['losetup'", "['/usr/sbin/losetup'")

        # Si hay variable cmd = "losetup" o losetup_cmd
        text = re.sub(r'=\s*"losetup"', '= "/usr/sbin/losetup"', text)
        text = re.sub(r"=\s*'losetup'", "= '/usr/sbin/losetup'", text)

        return text

    patch_file(losetup_py, force_usr_sbin_losetup, "force /usr/sbin/losetup")

    # 2a) Also auto-install partition tools in mount() (survives chroot recreation)
    # When pmbootstrap install recreates the native chroot during package builds,
    # tools like losetup (util-linux), parted, partx get wiped.
    def inject_apk_install(text: str) -> str:
        """Add apk add --upgrade losetup parted util-linux before mount() uses them"""
        target = 'logging.debug(f"(native) mount {img_path} (loop)")'
        if target not in text:
            return text
        if "apk add --upgrade losetup" in text:
            return text
        insert = (
            '    # Ensure partition tools survive chroot recreation\n'
            '    pmb.chroot.root(["apk", "add", "--upgrade", "losetup", "parted", "util-linux"], check=False)\n'
        )
        text = text.replace(target + '\n', target + '\n' + insert)
        return text

    patch_file(losetup_py, inject_apk_install, "auto-install partition tools in mount()")

    # 2b) Also install partition tools in device_by_back_file() as safety net
    def inject_apk_install_device(text: str) -> str:
        """Ensure partition tools are installed in device_by_back_file too"""
        target = 'def device_by_back_file(back_file: Path) -> Path:'
        if target not in text:
            return text
        if "apk add --upgrade losetup" in text:
            return text
        insert = (
            '    # Ensure partition tools survive chroot recreation\n'
            '    pmb.chroot.root(["apk", "add", "--upgrade", "losetup", "parted", "util-linux"], check=False)\n'
        )
        text = text.replace(target + '\n', target + '\n' + insert)
        return text

    patch_file(losetup_py, inject_apk_install_device, "auto-install partition tools in device_by_back_file()")

# 3) blockdevice.py: re-init chroot_native if deleted (survives chroot recreation)
bd = ROOT / "install" / "blockdevice.py"
if bd.exists():
    with open(bd) as f:
        c = f.read()
    
    # Add pmb.chroot import if not present  
    c = c.replace('import pmb.helpers.mount',
                  'import pmb.chroot\nimport pmb.helpers.mount')
    
    # Re-init native chroot before mkdir (from earlier working patch)
    old = re.compile(r'^(\s+)# Create empty image files\s*\n\s+pmb\.chroot\.user\(\["mkdir",\s*"-p",\s*"/home/pmos/rootfs"\]\)',
                     re.MULTILINE)
    
    def replacer_blockdev(m):
        ws = m.group(1)
        body_ws = ws + '    '
        return (
            f'{ws}# Re-init native chroot if pmbootstrap deleted it\n'
            f'{ws}if not Chroot.native().exists():\n'
            f'{body_ws}pmb.chroot.init(Chroot.native())\n'
            f'\n'
            f'{ws}# Create empty image files\n'
            f'{ws}pmb.chroot.user(["mkdir", "-p", "/home/pmos/rootfs"])'
        )
    
    new_c = old.sub(replacer_blockdev, c)
    if new_c != c:
        with open(bd, 'w') as f:
            f.write(new_c)
        print(f"✓ Patched {bd}: chroot_native re-init before mkdir")
    else:
        print(f"- No change {bd}: already patched or structure changed")

# 4) _install.py: fix rm in-pmbootstrap without -f (bug #2309 cleanup crash)
install_py = ROOT / "install" / "_install.py"
if install_py.exists():
    def fix_rm_in_pmbootstrap(text: str) -> str:
        """Use rm -f instead of rm for in-pmbootstrap cleanup"""
        old = '["rm", chroot / "in-pmbootstrap"]'
        new = '["rm", "-f", chroot / "in-pmbootstrap"]'
        if old not in text:
            return text
        if new in text:
            return text
        return text.replace(old, new)

    patch_file(install_py, fix_rm_in_pmbootstrap, "rm -f in-pmbootstrap (ignore if already removed)")

# 5) partition.py: ensure parted is installed before partition operations
part_py = ROOT / "install" / "partition.py"
if part_py.exists():
    def ensure_partition_tools(text: str) -> str:
        """Install parted and partx before partition operations"""
        target = 'def partition(layout: PartitionLayout, size_boot: int) -> None:'
        if target not in text:
            return text
        if "apk add --upgrade parted" in text:
            return text
        insert = (
            '    # Ensure parted and friends are installed (chroot may be recreated)\n'
            '    pmb.chroot.root(["apk", "add", "--upgrade", "losetup", "parted", "util-linux"], check=False)\n'
        )
        text = text.replace(target + '\n', target + '\n' + insert)
        return text

    patch_file(part_py, ensure_partition_tools, "ensure parted in partition() before use")

print("=== grep losetup/parted after patch ===")
for path in ROOT.rglob("*.py"):
    txt = path.read_text(errors="ignore")
    if "losetup" in txt or "/sbin/losetup" in txt or "/usr/sbin/losetup" in txt or "apk add" in txt:
        print(path)
        for i, line in enumerate(txt.splitlines(), start=1):
            if "losetup" in line or "apk add" in line:
                print(f"  {i}: {line}")
