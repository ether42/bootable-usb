import subprocess

exclude_patterns = ['venv/*']
extensions = [
    'sphinx.ext.graphviz',
    'sphinx.ext.todo',
]
graphviz_output_format = 'svg'
html_show_copyright = False
html_show_sphinx = False
html_static_path = ['static']
html_style = 'css/override.css'
html_theme = 'sphinx_rtd_theme'
master_doc = 'index'
project = 'Bootable USB'
release = subprocess.check_output(['git', 'describe', '--all', '--long']).decode('utf-8').strip()
source_suffix = '.rst'
todo_emit_warnings = True
todo_include_todos = True
version = release
