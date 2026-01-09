import { auth } from './auth.js';
import { sync } from './sync.js';
import { query } from './query.js';

class App {
  constructor() {
    this.user = null;
    this.init();
  }

  async init() {
    // Set up auth listeners
    auth.onAuthStateChanged((user) => {
      this.user = user;
      this.updateUI();
    });

    // Set up button handlers
    document.getElementById('signin-btn').addEventListener('click', () => {
      auth.signIn();
    });

    document.getElementById('sync-btn').addEventListener('click', async () => {
      await this.syncData();
    });

    document.getElementById('query-btn').addEventListener('click', async () => {
      await this.handleQuery();
    });

    document.getElementById('query-input').addEventListener('keypress', async (e) => {
      if (e.key === 'Enter') {
        await this.handleQuery();
      }
    });
  }

  updateUI() {
    const signinPrompt = document.getElementById('signin-prompt');
    const dashboard = document.getElementById('dashboard');
    const authStatus = document.getElementById('auth-status');

    if (this.user) {
      signinPrompt.classList.add('hidden');
      dashboard.classList.remove('hidden');
      authStatus.innerHTML = `
        <div>
          <span>${this.user.displayName}</span>
          <button onclick="auth.signOut()" class="btn-secondary" style="margin-left: 1rem">Sign Out</button>
        </div>
      `;
      
      // Auto-sync on sign in
      this.syncData();
    } else {
      signinPrompt.classList.remove('hidden');
      dashboard.classList.add('hidden');
      authStatus.innerHTML = '';
    }
  }

  async syncData() {
    const indicator = document.getElementById('sync-indicator');
    const syncBtn = document.getElementById('sync-btn');
    
    indicator.textContent = '🔄 Syncing...';
    syncBtn.disabled = true;

    try {
      const result = await sync.syncFromDrive();
      indicator.textContent = `✅ Synced ${result.filesDownloaded} files`;
      setTimeout(() => {
        indicator.textContent = '⚪ Up to date';
      }, 3000);
    } catch (error) {
      indicator.textContent = '❌ Sync failed';
      console.error('Sync error:', error);
    } finally {
      syncBtn.disabled = false;
    }
  }

  async handleQuery() {
    const input = document.getElementById('query-input');
    const question = input.value.trim();
    
    if (!question) return;

    const results = document.getElementById('results');
    results.innerHTML = '<div class="loading">Processing your question...</div>';

    try {
      const result = await query.ask(question);
      this.renderResult(result);
    } catch (error) {
      results.innerHTML = `<div class="error">Error: ${error.message}</div>`;
    }
  }

  renderResult(result) {
    const results = document.getElementById('results');
    
    // Create visualization based on type
    const container = document.createElement('div');
    container.className = 'chart-container';
    
    const title = document.createElement('h3');
    title.textContent = result.visualization.title;
    container.appendChild(title);

    if (result.visualization.type === 'big_number') {
      const bigNum = document.createElement('div');
      bigNum.className = 'big-number';
      bigNum.innerHTML = `
        <div class="value">${result.data.value}${result.visualization.format === 'percentage' ? '%' : ''}</div>
        <div class="label">${result.summary}</div>
      `;
      container.appendChild(bigNum);
    } else {
      // Placeholder for other chart types
      const canvas = document.createElement('canvas');
      canvas.id = 'chart';
      container.appendChild(canvas);
      // Chart.js rendering will be added in Phase 4
    }

    results.innerHTML = '';
    results.appendChild(container);
  }
}

// Initialize app
new App();
