import { db } from './sync.js';

// Placeholder for Gemini API key
const GEMINI_API_KEY = 'YOUR_GEMINI_API_KEY_HERE';
const GEMINI_API_URL = 'https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-pro:generateContent';

class QueryService {
    async ask(question) {
        // For now, return a demo result
        // Phase 5 will implement actual LLM integration

        // Simple pattern matching for demo
        if (question.toLowerCase().includes('completion rate')) {
            const data = await this.getCompletionRate();
            return {
                sql: 'SELECT COUNT(*) FILTER (WHERE isCompleted) * 100.0 / COUNT(*) FROM instances',
                visualization: {
                    type: 'big_number',
                    format: 'percentage',
                    title: 'Overall Completion Rate'
                },
                data: { value: data.rate },
                summary: `Your overall completion rate is ${data.rate}%`
            };
        }

        // Default fallback
        return {
            visualization: {
                type: 'big_number',
                title: 'Feature Coming Soon'
            },
            data: { value: '...' },
            summary: 'LLM-powered queries will be available in Phase 5'
        };
    }

    async getCompletionRate() {
        const files = await db.files.toArray();
        const instances = files.filter(f => f.name.startsWith('MoleculeInstance_'));

        if (instances.length === 0) {
            return { rate: 0 };
        }

        const completed = instances.filter(i => i.content.isCompleted).length;
        const rate = Math.round((completed / instances.length) * 100);

        return { rate };
    }

    async callGeminiAPI(prompt) {
        const response = await fetch(
            `${GEMINI_API_URL}?key=${GEMINI_API_KEY}`,
            {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json'
                },
                body: JSON.stringify({
                    contents: [{
                        parts: [{
                            text: prompt
                        }]
                    }],
                    generationConfig: {
                        response_mime_type: 'application/json'
                    }
                })
            }
        );

        if (!response.ok) {
            throw new Error(`Gemini API error: ${response.statusText}`);
        }

        const data = await response.json();
        const text = data.candidates[0].content.parts[0].text;
        return JSON.parse(text);
    }
}

export const query = new QueryService();
