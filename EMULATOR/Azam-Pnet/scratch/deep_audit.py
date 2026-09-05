import os, sys, re, json, glob

if sys.platform == "win32":
    try:
        sys.stdout.reconfigure(encoding='utf-8', errors='replace')
        sys.stderr.reconfigure(encoding='utf-8', errors='replace')
    except Exception:
        pass

def deep_audit():
    print("=" * 60)
    print("           AZAM-PNET DEEP COMPREHENSIVE AUDIT               ")
    print("=" * 60)

    # 1. Disk footprint audit
    print("\n--- [1] DISK FOOTPRINT & FILE REDUNDANCY ANALYSIS ---")
    deb_versions = {}
    generic_versions = {}
    total_size = 0
    
    for root, dirs, files in os.walk('.'):
        if '.git' in root: continue
        for f in files:
            fp = os.path.join(root, f)
            sz = os.path.getsize(fp)
            total_size += sz
            
            # Check Debian packages
            if fp.startswith(os.path.join('.', 'debian')):
                match = re.search(r'_(6\.8\.[0-9]+resolute[0-9]+)', f)
                if match:
                    v = match.group(1)
                    deb_versions[v] = deb_versions.get(v, 0) + sz
            
            # Check Generic packages
            if fp.startswith(os.path.join('.', 'generic')):
                match = re.search(r'(6\.8\.[0-9]+resolute[0-9]+|0\.channel)', root)
                if match:
                    v = match.group(1)
                    generic_versions[v] = generic_versions.get(v, 0) + sz

    print(f"Total Workspace Size: {total_size / (1024*1024):.2f} MB ({total_size / (1024*1024*1024):.2f} GB)")
    print("\nDebian Packages by Version:")
    for v, sz in sorted(deb_versions.items()):
        print(f"  Version {v:16s}: {sz / (1024*1024):8.2f} MB")
    
    print("\nGeneric Asset Directories by Version:")
    for v, sz in sorted(generic_versions.items()):
        print(f"  Channel/Version {v:16s}: {sz / (1024*1024):8.2f} MB")

    # 2. Image duplicates
    print("\n--- [2] IMAGE ASSETS IN WORKSPACE ---")
    for root, dirs, files in os.walk('.'):
        if '.git' in root: continue
        for f in files:
            if f.lower().endswith(('.png', '.ico', '.jpg', '.jpeg', '.svg')):
                fp = os.path.join(root, f)
                sz = os.path.getsize(fp)
                print(f"  {fp:50s} ({sz:7d} bytes)")

    # 3. Scripts Analysis
    print("\n--- [3] SCRIPTS AUDIT & ERROR DETECTION ---")
    issues_found = 0
    for sfile in sorted(os.listdir('scripts')):
        sfp = os.path.join('scripts', sfile)
        if not os.path.isfile(sfp):
            continue
        with open(sfp, 'r', encoding='utf-8', errors='ignore') as f:
            content = f.read()
        
        issues = []
        # Check inline python
        py_blocks = re.findall(r'(?:python3|python)\s+(?:-|<<\s*[\'"]?([A-Za-z0-9_]+)[\'"]?)\s*\n(.*?)\n\1', content, re.DOTALL)
        for tag, block in py_blocks:
            for mod in ['os', 'sys', 're', 'json', 'time', 'subprocess', 'shutil', 'glob']:
                if f'{mod}.' in block and f'import {mod}' not in block and f'from {mod}' not in block:
                    issues.append(f"Inline python uses `{mod}.` without importing `{mod}`")
        
        if '/opt/azambasha /opt/azambasha' in content:
            issues.append("Duplicate folder path in mkdir/symlink")
        
        if issues:
            issues_found += 1
            print(f"\n[ISSUES IN {sfile}]")
            for iss in issues:
                print(f"  - {iss}")

    if issues_found == 0:
        print("  [OK PASS] All scripts in scripts/ passed static analysis with ZERO issues!")

    # 4. Root install scripts audit
    print("\n--- [4] ROOT INSTALL SCRIPTS AUDIT ---")
    for rscript in ['install.sh', 'install-satellite.sh']:
        if os.path.exists(rscript):
            with open(rscript, 'r', encoding='utf-8', errors='ignore') as f:
                content = f.read()
            issues = []
            if '/opt/azambasha /opt/azambasha' in content:
                issues.append("Duplicate folder path in mkdir/symlink")
            
            # Check version references
            v_refs = set(re.findall(r'6\.8\.[0-9]+resolute[0-9]+', content))
            if v_refs:
                issues.append(f"Hardcoded package versions: {v_refs}")
            
            print(f"[{rscript}] {'ERRORS: ' + str(issues) if issues else '[OK PASS] Fully dynamic and validated.'}")

if __name__ == '__main__':
    deep_audit()
