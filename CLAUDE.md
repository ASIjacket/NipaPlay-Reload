# 本仓库相对官方上游的有意改动

上游是 `https://github.com/MCDFsteve/NipaPlay-Reload`。本文件记录**必须在每次同步上游后保留**的改动。
同步上游（`git merge upstream/main` 等）之后，请照下面的清单逐条核对。

---

## 1. `.github/workflows/build-windows.yml` — 手动构建 + 产物瘦身

**保留原因**

上游这个 workflow 只有 `workflow_call`，无法在 Actions 页面单独构建 Windows；且产物
`path: build/windows/*` 会把完整构建树 `x64/` 和免安装包解压后的同名目录一起打包，
artifact 约 1.2 GB，其中一个多 GB 没有任何消费方 —— 发布流程 `main.yml` 只取顶层的
`*.zip` / `*.exe` / `*.msix`。

改完后手动构建的 artifact 约 130 MB。

**改动内容**

`on:` 段补回手动触发入口：

```yaml
on:
  workflow_dispatch:
    inputs:
      portable-only:
        description: '产物只保留免安装版（跳过安装器和 MSIX）'
        type: boolean
        default: true
  workflow_call:
    # 刻意不暴露 portable-only：release 需要安装器和 MSIX
```

产物上传按触发方式拆成两步，替换掉上游原来那个 `Upload Windows Artifacts`：

```yaml
      - name: Upload portable Windows build
        if: inputs.portable-only
        uses: actions/upload-artifact@v4
        with:
          name: release-Windows-x64
          path: build/windows/NipaPlay_*_Windows_x64/
          if-no-files-found: error

      - name: Upload Windows Artifacts
        if: ${{ !inputs.portable-only }}
        uses: actions/upload-artifact@v4
        with:
          name: release-Windows-x64
          path: |
            build/windows/*.zip
            build/windows/*.exe
            build/windows/*.msix
          if-no-files-found: error
```

**两个容易改错的点**

- 判据必须用 `inputs.portable-only`，**不能**用 `github.event_name == 'workflow_dispatch'`：
  被 `workflow_call` 时 `event_name` 是**调用方**的事件，手动触发 `main.yml` 同样会得到
  `workflow_dispatch`，据此判断会让正式 release 丢掉安装器和 MSIX。
  `workflow_call` 段不定义该 input，未定义时求值为空，自然走完整产物分支。
- 手动分支传的是**免安装目录本身**，不是它的 `.zip`：artifact 下载下来本身就是 zip，
  再套一层要解压两次才能跑；而且内层已压过一次，外层再压等于白压（套娃 320 MB，
  直接传目录 130 MB）。

**同步后自检**

```bash
git diff --stat upstream/main..HEAD
# 期望：只有 .github/workflows/build-windows.yml 一个文件有差异
python3 -c "import yaml; d=yaml.safe_load(open('.github/workflows/build-windows.yml')); print(list(d[True].keys()))"
# 期望：['workflow_dispatch', 'workflow_call']
```

---

## 同步上游的做法

```bash
git remote add upstream https://github.com/MCDFsteve/NipaPlay-Reload   # 首次
git fetch upstream main
git merge upstream/main
```

若 `build-windows.yml` 冲突，以本文件记录的版本为准重新应用，不要直接取上游版本。
