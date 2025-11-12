const express = require('express');
const mysql = require('mysql2/promise');
const app = express();

app.use(express.json());
app.use(express.static('.'));

// Configuration MySQL depuis variables d'environnement
const dbConfig = {
  host: process.env.MYSQL_SERVER || 'host.wsl.internal',
  user: process.env.MYSQL_USERNAME || 'adminstudent',
  password: process.env.MYSQL_PASSWORD || 'admin',
  database: process.env.MYSQL_DATABASE || 'taskdb',
  ssl: { rejectUnauthorized: false }
};


let pool;

// Initialisation de la base de données
async function initDatabase() {
  try {
    pool = mysql.createPool(dbConfig);
    
    // Création des tables
    await pool.query(`
      CREATE TABLE IF NOT EXISTS users (
        id INT AUTO_INCREMENT PRIMARY KEY,
        name VARCHAR(100) NOT NULL,
        email VARCHAR(100) UNIQUE NOT NULL,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
      )
    `);

    await pool.query(`
      CREATE TABLE IF NOT EXISTS tasks (
        id INT AUTO_INCREMENT PRIMARY KEY,
        user_id INT NOT NULL,
        title VARCHAR(200) NOT NULL,
        description TEXT,
        status ENUM('pending', 'in_progress', 'completed') DEFAULT 'pending',
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
      )
    `);

    console.log('✓ Base de données initialisée');
  } catch (error) {
    console.error('Erreur initialisation DB:', error);
    throw error;
  }
}

// Routes API

// GET - Page d'accueil
app.get('/', (req, res) => {
  res.send(`
    <!DOCTYPE html>
    <html>
    <head>
      <title>TaskManager - CloudCorp</title>
      <style>
        body { font-family: Arial; max-width: 800px; margin: 50px auto; padding: 20px; }
        h1 { color: #0078d4; }
        .endpoint { background: #f5f5f5; padding: 10px; margin: 10px 0; border-left: 4px solid #0078d4; }
        code { background: #e0e0e0; padding: 2px 6px; border-radius: 3px; }
      </style>
    </head>
    <body>
      <h1>🚀 TaskManager API - CloudCorp</h1>
      <p>Application de gestion de tâches déployée sur Azure</p>
      
      <h2>Endpoints disponibles:</h2>
      
      <div class="endpoint">
        <strong>GET /health</strong> - Vérification santé de l'application
      </div>
      
      <div class="endpoint">
        <strong>GET /api/users</strong> - Liste tous les utilisateurs
      </div>
      
      <div class="endpoint">
        <strong>POST /api/users</strong> - Créer un utilisateur<br>
        Body: <code>{"name": "John Doe", "email": "john@example.com"}</code>
      </div>
      
      <div class="endpoint">
        <strong>GET /api/tasks</strong> - Liste toutes les tâches
      </div>
      
      <div class="endpoint">
        <strong>POST /api/tasks</strong> - Créer une tâche<br>
        Body: <code>{"user_id": 1, "title": "Ma tâche", "description": "Description", "status": "pending"}</code>
      </div>
      
      <div class="endpoint">
        <strong>PUT /api/tasks/:id</strong> - Mettre à jour une tâche
      </div>
      
      <div class="endpoint">
        <strong>DELETE /api/tasks/:id</strong> - Supprimer une tâche
      </div>
    </body>
    </html>
  `);
});

// Health check
app.get('/health', async (req, res) => {
  try {
    await pool.query('SELECT 1');
    res.json({ status: 'healthy', database: 'connected', timestamp: new Date() });
  } catch (error) {
    res.status(500).json({ status: 'unhealthy', error: error.message });
  }
});

// Users endpoints
app.get('/api/users', async (req, res) => {
  try {
    const [rows] = await pool.query('SELECT * FROM users ORDER BY created_at DESC');
    res.json(rows);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

app.post('/api/users', async (req, res) => {
  try {
    const { name, email } = req.body;
    const [result] = await pool.query(
      'INSERT INTO users (name, email) VALUES (?, ?)',
      [name, email]
    );
    res.status(201).json({ id: result.insertId, name, email });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// Tasks endpoints
app.get('/api/tasks', async (req, res) => {
  try {
    const [rows] = await pool.query(`
      SELECT t.*, u.name as user_name, u.email as user_email 
      FROM tasks t 
      JOIN users u ON t.user_id = u.id 
      ORDER BY t.created_at DESC
    `);
    res.json(rows);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

app.post('/api/tasks', async (req, res) => {
  try {
    const { user_id, title, description, status } = req.body;
    const [result] = await pool.query(
      'INSERT INTO tasks (user_id, title, description, status) VALUES (?, ?, ?, ?)',
      [user_id, title, description, status || 'pending']
    );
    res.status(201).json({ id: result.insertId, ...req.body });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

app.put('/api/tasks/:id', async (req, res) => {
  try {
    const { id } = req.params;
    const { title, description, status } = req.body;
    await pool.query(
      'UPDATE tasks SET title = ?, description = ?, status = ? WHERE id = ?',
      [title, description, status, id]
    );
    res.json({ message: 'Task updated', id });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

app.delete('/api/tasks/:id', async (req, res) => {
  try {
    const { id } = req.params;
    await pool.query('DELETE FROM tasks WHERE id = ?', [id]);
    res.json({ message: 'Task deleted', id });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// Démarrage du serveur
const PORT = process.env.PORT || 8080;

initDatabase().then(() => {
  app.listen(PORT, () => {
    console.log(`✓ Serveur démarré sur le port ${PORT}`);
  });
}).catch(error => {
  console.error('Échec du démarrage:', error);
  process.exit(1);
});