import os
import tempfile

import pytest
from flask import json

import sys
sys.path.insert(0, os.path.abspath('src'))
import app as app_module

@pytest.fixture
def client():
    db_fd, app_module.app.config['DATABASE'] = tempfile.mkstemp()
    app_module.app.config['TESTING'] = True
    with app_module.app.test_client() as client:
        yield client
    os.close(db_fd)
    if os.path.exists('db.sqlite3'):
        os.remove('db.sqlite3')


def test_create_and_list_projects(client):
    rv = client.post('/projects', json={'name': 'Test'})
    assert rv.status_code == 201
    project_id = rv.get_json()['id']

    rv = client.get('/projects')
    assert rv.status_code == 200
    data = rv.get_json()
    assert any(p['id'] == project_id for p in data)


def test_add_task_and_complete(client):
    rv = client.post('/projects', json={'name': 'Another'})
    pid = rv.get_json()['id']

    rv = client.post(f'/projects/{pid}/tasks', json={'description': 'Task 1'})
    assert rv.status_code == 201
    tid = rv.get_json()['id']

    rv = client.post(f'/tasks/{tid}/complete')
    assert rv.status_code == 200
    assert rv.get_json()['completed'] is True
