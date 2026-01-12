// Google OAuth Authentication
// Instructions: Replace with your actual API credentials from Google Cloud Console
const CLIENT_ID = import.meta.env.VITE_GAPI_CLIENT_ID;
const API_KEY = import.meta.env.VITE_GAPI_API_KEY;

const DISCOVERY_DOCS = ['https://www.googleapis.com/discovery/v1/apis/drive/v3/rest'];
const SCOPES = 'https://www.googleapis.com/auth/drive.readonly';

class AuthService {
    constructor() {
        this.user = null;
        this.authChangeCallbacks = [];
        this.init();
    }

    async init() {
        // Load Google API client
        await this.loadGoogleAPI();

        // Initialize the client
        await gapi.client.init({
            apiKey: API_KEY,
            clientId: CLIENT_ID,
            discoveryDocs: DISCOVERY_DOCS,
            scope: SCOPES
        });

        // Listen for sign-in state changes
        gapi.auth2.getAuthInstance().isSignedIn.listen((isSignedIn) => {
            this.updateSignInStatus(isSignedIn);
        });

        // Handle the initial sign-in state
        this.updateSignInStatus(gapi.auth2.getAuthInstance().isSignedIn.get());
    }

    loadGoogleAPI() {
        return new Promise((resolve) => {
            const script = document.createElement('script');
            script.src = 'https://apis.google.com/js/api.js';
            script.onload = () => {
                gapi.load('client:auth2', resolve);
            };
            document.body.appendChild(script);
        });
    }

    updateSignInStatus(isSignedIn) {
        if (isSignedIn) {
            const user = gapi.auth2.getAuthInstance().currentUser.get();
            const profile = user.getBasicProfile();
            this.user = {
                id: profile.getId(),
                email: profile.getEmail(),
                displayName: profile.getName(),
                imageUrl: profile.getImageUrl()
            };
        } else {
            this.user = null;
        }

        // Notify all listeners
        this.authChangeCallbacks.forEach(callback => callback(this.user));
    }

    onAuthStateChanged(callback) {
        this.authChangeCallbacks.push(callback);
        // Immediately call with current state
        callback(this.user);
    }

    signIn() {
        gapi.auth2.getAuthInstance().signIn();
    }

    signOut() {
        gapi.auth2.getAuthInstance().signOut();
    }

    getAccessToken() {
        if (!this.user) return null;
        return gapi.auth2.getAuthInstance().currentUser.get().getAuthResponse().access_token;
    }
}

export const auth = new AuthService();
