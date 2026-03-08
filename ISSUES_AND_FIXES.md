# Ansible Role Review - Issues and Fixes

## Issue #1: CRITICAL - Missing Template File Reference

**Severity:** HIGH - Will cause deployment failure

### Location
```
File:      roles/openclaw-config/tasks/main.yml
Line:      30
```

### Problem
The task references a file that doesn't exist:

```yaml
- name: Deploy Smokescreen custom main.go
  ansible.builtin.copy:
    src: main.smokescreen.go        # ❌ THIS FILE DOESN'T EXIST
    dest: "{{ openclaw_base_dir }}/build/smokescreen/main.go"
    owner: root
    group: root
    mode: "0644"
  notify: Rebuild egress
```

### Current State
- **Referenced file:** `main.smokescreen.go`
- **Actual file:** `roles/openclaw-config/templates/smokescreen-main.go.j2`
- **Status:** File not found → Task will FAIL

### Solutions

#### Option 1: Rename the template file (RECOMMENDED)
```bash
cd roles/openclaw-config/templates/
mv smokescreen-main.go.j2 main.smokescreen.go
```

Then update the task to use copy without .j2:
```yaml
- name: Deploy Smokescreen custom main.go
  ansible.builtin.copy:
    src: main.smokescreen.go   # ✓ File will exist
    dest: "{{ openclaw_base_dir }}/build/smokescreen/main.go"
    owner: root
    group: root
    mode: "0644"
  notify: Rebuild egress
```

#### Option 2: Update task to use template task
```yaml
- name: Deploy Smokescreen custom main.go
  ansible.builtin.template:
    src: smokescreen-main.go.j2   # ✓ File exists (no rename needed)
    dest: "{{ openclaw_base_dir }}/build/smokescreen/main.go"
    owner: root
    group: root
    mode: "0644"
  notify: Rebuild egress
```

#### Option 3: Update src reference to match filename
```yaml
- name: Deploy Smokescreen custom main.go
  ansible.builtin.copy:
    src: smokescreen-main.go.j2   # ✓ File exists
    dest: "{{ openclaw_base_dir }}/build/smokescreen/main.go"
    owner: root
    group: root
    mode: "0644"
  notify: Rebuild egress
```

### Recommended Fix
**Use Option 1** - The task uses `ansible.builtin.copy`, not `template`. The `.j2` extension suggests this should be a template, but since it's being copied as-is, renaming to remove the `.j2` extension is cleaner.

**Steps:**
1. Rename: `mv smokescreen-main.go.j2` to `main.smokescreen.go`
2. No change needed to the task (already correct reference)
3. Test deployment

---

## Issue #2: INFORMATIONAL - Handler Listen Pattern

**Severity:** INFORMATIONAL - Correct implementation, no action needed

### Location
```
File:      roles/openclaw-config/handlers/main.yml
Lines:     19, 27
```

### Status
✓ **This is CORRECTLY implemented** - No action required

### Details
The handlers use the `listen:` keyword to group multiple handlers under a single notify name:

```yaml
- name: Probe egress
  ansible.builtin.command: docker compose ps -q openclaw-egress
  args:
    chdir: "{{ openclaw_base_dir }}"
  register: egress_probe
  failed_when: false
  changed_when: false
  listen: Restart egress          # ← Groups this handler

- name: Restart egress container
  ansible.builtin.command: docker compose restart openclaw-egress
  args:
    chdir: "{{ openclaw_base_dir }}"
  when: egress_probe.stdout | default('') | trim != ''
  changed_when: true
  listen: Restart egress          # ← Both handlers execute on notify
```

### How It Works
When a task executes:
```yaml
notify: Restart egress
```

Both handlers with `listen: Restart egress` execute in sequence:
1. Probe egress (checks if container exists)
2. Restart egress container (only if container exists)

This is a **best practice pattern** for conditional handler execution.

### Recommendation
No changes needed. This is an excellent implementation.

---

## Issue #3: WARNING - lineinfile Mode Parameter

**Severity:** LOW - Works but may not guarantee permissions

### Location
```
File:      roles/monitoring/tasks/main.yml
Lines:     12-18
```

### Problem
The `lineinfile` task includes a `mode:` parameter, but this only applies when the file is **created or modified**:

```yaml
- name: Append Grafana password to .env
  ansible.builtin.lineinfile:
    path: "{{ openclaw_base_dir }}/.env"
    regexp: "^GRAFANA_ADMIN_PASSWORD="
    line: "GRAFANA_ADMIN_PASSWORD={{ grafana_admin_password }}"
    mode: "0600"                   # ⚠ Only applied on create/modify
  no_log: true
```

### Issue
If the file already exists and the regexp matches an existing line, `lineinfile` will skip modification, and the `mode:` parameter won't be applied. The file permissions may not be guaranteed.

### Solutions

#### Option 1: Add separate file task (RECOMMENDED)
```yaml
- name: Append Grafana password to .env
  ansible.builtin.lineinfile:
    path: "{{ openclaw_base_dir }}/.env"
    regexp: "^GRAFANA_ADMIN_PASSWORD="
    line: "GRAFANA_ADMIN_PASSWORD={{ grafana_admin_password }}"
  no_log: true

- name: Ensure .env file permissions
  ansible.builtin.file:
    path: "{{ openclaw_base_dir }}/.env"
    mode: "0600"
  when: monitoring_enabled | bool
```

#### Option 2: Move mode to file task with create option
```yaml
- name: Ensure .env file exists with correct permissions
  ansible.builtin.file:
    path: "{{ openclaw_base_dir }}/.env"
    state: touch
    mode: "0600"
    owner: root
    group: root

- name: Append Grafana password to .env
  ansible.builtin.lineinfile:
    path: "{{ openclaw_base_dir }}/.env"
    regexp: "^GRAFANA_ADMIN_PASSWORD="
    line: "GRAFANA_ADMIN_PASSWORD={{ grafana_admin_password }}"
  no_log: true
```

### Recommendation
**Use Option 1** - It's simple and ensures permissions are always correct:

```yaml
- name: Append Grafana password to .env
  ansible.builtin.lineinfile:
    path: "{{ openclaw_base_dir }}/.env"
    regexp: "^GRAFANA_ADMIN_PASSWORD="
    line: "GRAFANA_ADMIN_PASSWORD={{ grafana_admin_password }}"
    mode: "0600"  # Remove this line
  no_log: true

- name: Ensure .env file permissions  # Add this new task
  ansible.builtin.file:
    path: "{{ openclaw_base_dir }}/.env"
    mode: "0600"
  when: monitoring_enabled | bool
```

---

## Summary Table

| Issue | Severity | Location | Fix | Urgency |
|-------|----------|----------|-----|---------|
| #1: Missing template file | HIGH | openclaw-config/tasks/main.yml:30 | Rename file or update src | **CRITICAL** |
| #2: Handler listen pattern | N/A | openclaw-config/handlers/main.yml:19,27 | None (correct implementation) | N/A |
| #3: lineinfile mode | LOW | monitoring/tasks/main.yml:12-18 | Add separate file task | Optional |

---

## Testing After Fixes

```bash
# 1. After fixing Issue #1, verify the file exists:
ls -la roles/openclaw-config/templates/main.smokescreen.go

# 2. Validate playbook syntax:
ansible-playbook playbook.yml --syntax-check

# 3. Dry run to catch any remaining issues:
ansible-playbook playbook.yml --ask-vault-pass --check --diff

# 4. Verify permissions after Issue #3 fix:
ansible-playbook playbook.yml --ask-vault-pass --tags monitoring
ls -la /opt/openclaw/.env  # Should show -rw------- (0600)
```

---

## Files Modified

After applying these fixes, the following files should be updated:

1. **roles/openclaw-config/templates/** - Rename file (Issue #1)
2. **roles/monitoring/tasks/main.yml** - Add file task (Issue #3)

No changes needed to:
- roles/openclaw-config/handlers/main.yml (Issue #2 is correct)

