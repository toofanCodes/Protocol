import { auth } from './auth.js';
import Dexie from 'dexie';

// IndexedDB database for local caching
const db = new Dexie('ProtocolAnalytics');
db.version(1).stores({
    files: 'id, name, modifiedTime, content',
    syncMeta: 'key, value'
});

class SyncService {
    constructor() {
        this.folderName = 'Toofan_Empire_Sync/Records';
    }

    async syncFromDrive() {
        const accessToken = auth.getAccessToken();
        if (!accessToken) {
            throw new Error('Not authenticated');
        }

        // Get last sync time
        const lastSync = await db.syncMeta.get('lastSyncTime');
        const lastSyncTime = lastSync ? lastSync.value : null;

        // Build query for files modified since last sync
        let q = `'me' in owners and trashed = false`;
        if (lastSyncTime) {
            q += ` and modifiedTime > '${new Date(lastSyncTime).toISOString()}'`;
        }

        // List files from Drive
        const response = await fetch(
            `https://www.googleapis.com/drive/v3/files?` +
            `q=${encodeURIComponent(q)}&` +
            `fields=files(id,name,modifiedTime)&` +
            `pageSize=1000`,
            {
                headers: {
                    'Authorization': `Bearer ${accessToken}`
                }
            }
        );

        if (!response.ok) {
            throw new Error(`Drive API error: ${response.statusText}`);
        }

        const data = await response.json();
        const files = data.files || [];

        // Filter for JSON files in our folder
        const protocolFiles = files.filter(f =>
            f.name.endsWith('.json') &&
            (f.name.startsWith('MoleculeTemplate_') ||
                f.name.startsWith('MoleculeInstance_') ||
                f.name.startsWith('AtomTemplate_'))
        );

        let filesDownloaded = 0;

        // Download and cache each file
        for (const file of protocolFiles) {
            try {
                const content = await this.downloadFile(file.id, accessToken);

                // Store in IndexedDB
                await db.files.put({
                    id: file.id,
                    name: file.name,
                    modifiedTime: file.modifiedTime,
                    content: JSON.parse(content)
                });

                filesDownloaded++;
            } catch (error) {
                console.error(`Failed to download ${file.name}:`, error);
            }
        }

        // Update last sync time
        await db.syncMeta.put({ key: 'lastSyncTime', value: new Date().toISOString() });

        return { filesDownloaded };
    }

    async downloadFile(fileId, accessToken) {
        const response = await fetch(
            `https://www.googleapis.com/drive/v3/files/${fileId}?alt=media`,
            {
                headers: {
                    'Authorization': `Bearer ${accessToken}`
                }
            }
        );

        if (!response.ok) {
            throw new Error(`Failed to download file: ${response.statusText}`);
        }

        return await response.text();
    }

    async getAllCachedData() {
        return await db.files.toArray();
    }
}

export const sync = new SyncService();
export { db };
