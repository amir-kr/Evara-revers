from flask import Flask, render_template, request, jsonify, redirect, url_for, session
from flask_login import LoginManager, UserMixin, login_user, logout_user, login_required
import sqlite3
from tunnels import create_tunnel, delete_tunnel, get_tunnel_status

app = Flask(__name__, template_folder='templates')
app.secret_key = 'amir-tunnel-secret-key'
login_manager = LoginManager()
login_manager.init_app(app)
login_manager.login_view = 'login'

# مدل کاربر
class User(UserMixin):
    def __init__(self, id, username):
        self.id = id
        self.username = username

@login_manager.user_loader
def load_user(user_id):
    conn = sqlite3.connect('/usr/local/amir-tunnel/database.db')
    c = conn.cursor()
    c.execute("SELECT id, username FROM users WHERE id = ?", (user_id,))
    user = c.fetchone()
    conn.close()
    if user:
        return User(user[0], user[1])
    return None

# مسیرهای وب
@app.route('/login', methods=['GET', 'POST'])
def login():
    if request.method == 'POST':
        username = request.form['username']
        password = request.form['password']
        conn = sqlite3.connect('/usr/local/amir-tunnel/database.db')
        c = conn.cursor()
        c.execute("SELECT id, username FROM users WHERE username = ? AND password = ?", (username, password))
        user = c.fetchone()
        conn.close()
        if user:
            login_user(User(user[0], user[1]))
            return redirect(url_for('dashboard'))
        return render_template('login.html', error='نام کاربری یا رمز عبور اشتباه است.')
    return render_template('login.html')

@app.route('/logout')
@login_required
def logout():
    logout_user()
    return redirect(url_for('login'))

@app.route('/')
@login_required
def dashboard():
    conn = sqlite3.connect('/usr/local/amir-tunnel/database.db')
    c = conn.cursor()
    c.execute("SELECT id, name, type, port, mode, status FROM tunnels")
    tunnels = c.fetchall()
    conn.close()
    return render_template('dashboard.html', tunnels=tunnels)

@app.route('/api/add-tunnel', methods=['POST'])
@login_required
def add_tunnel():
    name = request.form['name']
    tunnel_type = request.form['type']
    port = request.form['port']
    mode = request.form['mode']
    try:
        result = create_tunnel(name, tunnel_type, port, mode)
        if result['status'] == 'success':
            conn = sqlite3.connect('/usr/local/amir-tunnel/database.db')
            c = conn.cursor()
            c.execute("INSERT INTO tunnels (name, type, port, mode, status) VALUES (?, ?, ?, ?, ?)", 
                     (name, tunnel_type, port, mode, 'active'))
            conn.commit()
            conn.close()
            return jsonify({'status': 'success', 'output': result['output']})
        return jsonify({'status': 'error', 'output': result['output']})
    except Exception as e:
        return jsonify({'status': 'error', 'output': str(e)})

@app.route('/api/delete-tunnel/<int:id>', methods=['POST'])
@login_required
def delete_tunnel(id):
    try:
        conn = sqlite3.connect('/usr/local/amir-tunnel/database.db')
        c = conn.cursor()
        c.execute("SELECT name FROM tunnels WHERE id = ?", (id,))
        tunnel = c.fetchone()
        if tunnel:
            result = delete_tunnel(tunnel[0])
            if result['status'] == 'success':
                c.execute("DELETE FROM tunnels WHERE id = ?", (id,))
                conn.commit()
                conn.close()
                return jsonify({'status': 'success', 'output': result['output']})
            conn.close()
            return jsonify({'status': 'error', 'output': result['output']})
        conn.close()
        return jsonify({'status': 'error', 'output': 'تونل یافت نشد.'})
    except Exception as e:
        return jsonify({'status': 'error', 'output': str(e)})

@app.route('/monitor/<int:id>')
@login_required
def monitor(id):
    conn = sqlite3.connect('/usr/local/amir-tunnel/database.db')
    c = conn.cursor()
    c.execute("SELECT name, type, port, mode, status FROM tunnels WHERE id = ?", (id,))
    tunnel = c.fetchone()
    conn.close()
    if tunnel:
        status = get_tunnel_status(tunnel[0])
        return render_template('monitor.html', tunnel=tunnel, status=status)
    return redirect(url_for('dashboard'))

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)
