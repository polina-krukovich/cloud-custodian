OutputDocs = provider(fields = ["files", "name"])

def add_exclude_pkgs_command(excluded_pkgs):
    """If there are excluded packages, add extra sed command to exclude these pkges from runfile"""
    if excluded_pkgs == []:
        return ""

    #  Change pkg name to format understandable by Bazel
    #  e.g. azure_cosmosdb_nspkg-2.1.3  -> __azure_cosmosdb_nspkg_2_1_3
    excluded_pkgs = ["\"__%s\"" % i.replace("-", "_").replace(".", "_").strip() for i in excluded_pkgs]
    excluded_pkgs = "[%s]" % ",".join(excluded_pkgs)

    #  it is last point in the chain of fetching deps from a sandbox.
    #  So it's the best place to exclude pkgs
    #  GetWindowsPathWithUNCPrefix was generated by bazel
    exclude_pkgs_command = \
        "| sed $'s/" + \
        "  python_path_entries = \[GetWindowsPathWithUNCPrefix(d) for d in python_path_entries\]/" + \
        "  python_path_entries = [GetWindowsPathWithUNCPrefix\(d\)" + \
        " for d in python_path_entries if not list\(filter\(d.endswith, %s\)\)]/g'" % excluded_pkgs
    return exclude_pkgs_command

def patch_executable(ctx):
    old_runner = ctx.executable.tool
    new_runner = ctx.actions.declare_file(ctx.attr.name)
    excluded_pkgs_command = add_exclude_pkgs_command(ctx.attr.excluded_pkgs)
    old_runfiles_path = "%s.runfiles" % ctx.executable.tool.path
    new_runfiles = ctx.actions.declare_directory("%s.runfiles" % new_runner.basename)
    ctx.actions.run_shell(
        progress_message = "Patching file content - %s" % old_runner.short_path,
        command = "sed $'s/*/*/g' '{old_runner}' {excld_pkgs_cmd} > '{new_runner}'".format(
                      old_runner = old_runner.path,
                      excld_pkgs_cmd = excluded_pkgs_command,
                      new_runner = new_runner.path,
                  ) +
                  # an executable file searches for runfiles in <executable_name>.runfiles directory
                  # therefore we copy <old_executable_name>.runfiles dir into <new_executable_name>.runfiles dir
                  " && cp -rf {old_runfiles}/* {new_runfiles}".format(
                      old_runfiles = old_runfiles_path,
                      new_runfiles = new_runfiles.path,
                  ),
        tools = [old_runner],
        outputs = [new_runner, new_runfiles],
    )
    return new_runner, new_runfiles

#   Copy external and generated files, generate html docs
def _impl_sphinx_generated_docs(ctx):
    ext_docs = ctx.actions.declare_directory("docs/")
    source = "/source"
    tools = "/tools"
    doctrees_dir = ctx.actions.declare_directory("build/doctrees")
    html_dir = ctx.actions.declare_directory("build/html")
    inputs = []
    commands = []
    directories = []

    #   Make commands for create directories
    for file in ctx.files.srcs:
        inputs.append(file)
        if file.dirname not in directories:
            directories.append(file.dirname)
            commands.append(
                "mkdir -p %s/%s" % (ext_docs.dirname, file.dirname),
            )

    #   Make commands for copy external files from docs
    for file in ctx.files.srcs:
        commands.append(
            "cp %s %s/%s" % (file.path, ext_docs.dirname, file.dirname),
        )

    #   Rename readme.md files and make commands for copy,
    #   and make dir and copy file for docs/source/tools
    for file in ctx.files.readme_files:
        inputs.append(file)
        if file.basename.lower() >= "readme.md":
            name = file.dirname.split("/")[-1].replace("_", "-") + ".md"
            path = ext_docs.path + source + tools + "/" + name
            commands.append(
                "cp %s %s" % (file.path, path),
            )
        else:
            path = ext_docs.path + source + tools + "/" + file.dirname.split("/")[-1]
            commands.append(
                "mkdir -p %s && cp %s %s" % (path, file.path, path),
            )

    #   Make commands for creating directories and copying generated files
    for src in ctx.attr.inputs:
        input_depset = src[OutputDocs].files
        list = src[OutputDocs].files.to_list()
        commands.append(
            "mkdir -p %s%s/%s && cp -R %s \"$_\"" % (ext_docs.path, source, src[OutputDocs].name, list[0].path),
        )
        inputs.append(list[0])

    #   Run commands
    ctx.actions.run_shell(
        inputs = depset(inputs),
        outputs = [ext_docs],
        command = "\n".join(commands),
    )
    new_runner, new_runfiles = patch_executable(ctx)

    #   Run generating html docs
    ctx.actions.run(
        inputs = [ext_docs, new_runfiles],
        outputs = [doctrees_dir, html_dir],
        #   Arguments for sphinx-build
        arguments = ["-j", "auto", "-b", "html", "-d", doctrees_dir.path, ext_docs.path + source, html_dir.path],
        executable = new_runner,
    )
    return [DefaultInfo(files = depset([doctrees_dir, html_dir]))]

sphinx_generate_docs = rule(
    implementation = _impl_sphinx_generated_docs,
    attrs = {
        "tool": attr.label(
            executable = True,
            cfg = "target",
            allow_files = True,
        ),
        #   Generated files from classes
        "inputs": attr.label_list(
            allow_empty = False,
        ),
        #   Collected all files from docs
        "srcs": attr.label_list(
            allow_empty = False,
            allow_files = True,
        ),
        #   Collected readme.md from tools
        "readme_files": attr.label_list(
            allow_empty = False,
            allow_files = True,
        ),
        "excluded_pkgs": attr.string_list(default = []),
    },
)

#  Generate rst files from classes
def _impl_rst_files_gen(ctx):
    old_runner = ctx.executable.tool
    tree = ctx.actions.declare_directory(ctx.attr.provider + "/resources")
    ctx.actions.run(
        inputs = [],
        outputs = [tree],
        arguments = [tree.path, ctx.attr.provider, ctx.attr.resource_type],
        executable = old_runner,
    )
    return [OutputDocs(files = depset([tree]), name = ctx.attr.provider)]

docgen = rule(
    implementation = _impl_rst_files_gen,
    attrs = {
        #   Run docgen.py
        "tool": attr.label(
            executable = True,
            cfg = "target",
            allow_files = True,
        ),
        #   Attribute provider for main in docgen.py
        "provider": attr.string(
            mandatory = True,
        ),
        #   Attribute resource_type for main in docgen.py
        "resource_type": attr.string(
            mandatory = True,
        ),
    },
)
