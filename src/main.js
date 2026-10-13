import '@fontsource/space-grotesk/300.css';
import '@fontsource/space-grotesk/400.css';
import '@fontsource/space-grotesk/500.css';
import '@fontsource/space-grotesk/600.css';
import '@fontsource/ibm-plex-mono/400.css';
import '@fontsource/ibm-plex-mono/500.css';
import '@fontsource/ibm-plex-mono/600.css';
import './styles.css';
import { Game } from './game.js';

function webglAvailable() {
  try {
    const c = document.createElement('canvas');
    return !!(window.WebGL2RenderingContext && c.getContext('webgl2'));
  } catch {
    return false;
  }
}

const canvas = document.getElementById('game');
if (!webglAvailable()) {
  document.getElementById('loadText').textContent = 'WebGL 2 is required to dive. Please use a current desktop browser with hardware acceleration enabled.';
} else {
  const game = new Game(canvas);
  game.init().catch((err) => {
    console.error(err);
    document.getElementById('loadText').textContent = `Failed to start: ${err.message}`;
  });
}
