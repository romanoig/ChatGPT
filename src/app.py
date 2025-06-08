from flask import Flask, request, jsonify, abort
from models import Project, Task, init_db, SessionLocal

app = Flask(__name__)
init_db()

@app.post('/projects')
def create_project():
    data = request.get_json(force=True)
    if not data or 'name' not in data:
        abort(400, 'Missing project name')
    session = SessionLocal()
    project = Project(name=data['name'])
    session.add(project)
    session.commit()
    return jsonify({'id': project.id, 'name': project.name}), 201

@app.get('/projects')
def list_projects():
    session = SessionLocal()
    projects = session.query(Project).all()
    return jsonify([{'id': p.id, 'name': p.name} for p in projects])

@app.post('/projects/<int:project_id>/tasks')
def create_task(project_id):
    data = request.get_json(force=True)
    if not data or 'description' not in data:
        abort(400, 'Missing task description')
    session = SessionLocal()
    project = session.get(Project, project_id)
    if project is None:
        abort(404, 'Project not found')
    task = Task(description=data['description'], project=project)
    session.add(task)
    session.commit()
    return jsonify({'id': task.id, 'description': task.description}), 201

@app.get('/projects/<int:project_id>/tasks')
def list_tasks(project_id):
    session = SessionLocal()
    project = session.get(Project, project_id)
    if project is None:
        abort(404, 'Project not found')
    return jsonify([
        {'id': t.id, 'description': t.description, 'completed': t.completed}
        for t in project.tasks
    ])

@app.post('/tasks/<int:task_id>/complete')
def complete_task(task_id):
    session = SessionLocal()
    task = session.get(Task, task_id)
    if task is None:
        abort(404, 'Task not found')
    task.completed = True
    session.commit()
    return jsonify({'id': task.id, 'completed': task.completed})

if __name__ == '__main__':
    app.run(debug=True)
