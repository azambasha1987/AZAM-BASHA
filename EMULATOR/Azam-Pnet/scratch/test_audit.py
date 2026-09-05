import os, re, ast

sh_files = [os.path.join('scripts', f) for f in os.listdir('scripts') if f.endswith('.sh')]
sh_files += ['install.sh', 'install-satellite.sh']

print(f"Checking {len(sh_files)} scripts for inline python blocks and AST validation...")
total_blocks = 0
errors = 0

for fp in sh_files:
    with open(fp, 'r', encoding='utf-8', errors='ignore') as f:
        content = f.read()
    
    # Pattern to match inline python blocks
    blocks = re.findall(r'python3\s+-\s*<<\s*[\'"]?([A-Za-z0-9_]+)[\'"]?\s*\n(.*?)\n\1', content, re.DOTALL)
    for tag, block in blocks:
        total_blocks += 1
        try:
            tree = ast.parse(block)
            
            # Extract all imported names
            imports = set()
            for node in ast.walk(tree):
                if isinstance(node, ast.Import):
                    for n in node.names:
                        imports.add(n.name)
                        if n.asname:
                            imports.add(n.asname)
                elif isinstance(node, ast.ImportFrom):
                    if node.module:
                        imports.add(node.module)
                    for n in node.names:
                        imports.add(n.name)
                        if n.asname:
                            imports.add(n.asname)
            
            # Check for standard library modules used as Name nodes without import
            common_modules = {'os', 'sys', 're', 'json', 'time', 'subprocess', 'shutil', 'glob', 'hashlib', 'socket', 'struct'}
            used_names = set()
            for node in ast.walk(tree):
                if isinstance(node, ast.Name):
                    used_names.add(node.id)
                elif isinstance(node, ast.Attribute) and isinstance(node.value, ast.Name):
                    used_names.add(node.value.id)
            
            unimported = (used_names & common_modules) - imports
            if unimported:
                print(f"[UNIMPORTED MODULE] {fp} tag {tag}: Uses {unimported} without importing!")
                errors += 1
        except Exception as e:
            print(f"[AST SYNTAX ERROR] {fp} tag {tag}: {e}")
            errors += 1

print(f"\nAudit complete: Checked {total_blocks} inline blocks across {len(sh_files)} scripts. Errors found: {errors}")
