from backend.main import create_app


def test_backend_package_imports_without_manual_path(tmp_path):
    app = create_app(tmp_path / "import-path.sqlite3")
    assert app.title == "Ruanchuang Backend"
