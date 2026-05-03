import 'core-js/es';
import 'core-js/web/immediate';
import 'core-js/web/queue-microtask';
import 'core-js/web/timers';
import 'regenerator-runtime/runtime';
import './polyfills';

import { loadCSS } from 'fg-loadcss';
import { render } from 'inferno';
import { setupHotReloading } from 'tgui-dev-server/link/client';
import { backendUpdate } from './backend';
import { act, tridentVersion } from './byond';
import { setupDrag } from './drag';
import { createLogger } from './logging';
import { getRoute } from './routes';
import { createStore } from './store';

const logger = createLogger();
const store = createStore();
const reactRoot = document.getElementById('react-root');

let initialRender = true;
let handedOverToOldTgui = false;

const renderLayout = () => {
  // Short-circuit the renderer
  if (handedOverToOldTgui) {
    return;
  }
  // Don't render until we've received actual data from the server.
  // Middleware dispatches on startup can trigger this before data arrives.
  if (!store.getState().config) {
    return;
  }
  // Mark the beginning of the render
  let startedAt;
  if (process.env.NODE_ENV !== 'production') {
    startedAt = Date.now();
  }
  try {
    const state = store.getState();
    // Initial render setup
    if (initialRender) {
      logger.log('initial render', state);

      // ----- Old TGUI chain-loader: begin -----
      const route = getRoute(state);
      // Route was not found, load old TGUI
      if (!route) {
        // Short-circuit the renderer
        handedOverToOldTgui = true;
        // Unsubscribe from updates
        window.update = window.initialize = () => {};
        // IE8: Use a redirection method
        if (tridentVersion <= 4) {
          setTimeout(() => {
            location.href = 'tgui-fallback.html?ref=' + window.__ref__;
          }, 10);
          return;
        }
        // Inject current state into the data holder
        const holder = document.getElementById('data');
        holder.textContent = JSON.stringify(state);
        // Load old TGUI by injecting new scripts
        loadCSS('v4shim.css');
        loadCSS('tgui.css');
        const head = document.getElementsByTagName('head')[0];
        const script = document.createElement('script');
        script.type = 'text/javascript';
        script.src = 'tgui.js';
        head.appendChild(script);
        // Bail
        return;
      }
      // ----- Old TGUI chain-loader: end -----

      // Setup dragging
      setupDrag(state);
    }
    // Start rendering
    const { Layout } = require('./layout');
    const element = <Layout state={state} dispatch={store.dispatch} />;
    render(element, reactRoot);
  }
  catch (err) {
    logger.error('rendering error', err);
    const stack = (err && (err.stack || err.message)) || String(err);
    // eslint-disable-next-line max-len
    const errHtml = '<pre style="color:red;background:#111;padding:1em;font-size:13px;white-space:pre-wrap">TGUI RENDER ERROR:\n\n'
      + stack + '</pre>';
    document.body.innerHTML = errHtml;
  }
  // Report rendering time
  if (process.env.NODE_ENV !== 'production') {
    const finishedAt = Date.now();
    const diff = finishedAt - startedAt;
    const diffFrames = (diff / 16.6667).toFixed(2);
    logger.debug(`rendered in ${diff}ms (${diffFrames} frames)`);
    if (initialRender) {
      const diff = finishedAt - window.__inception__;
      const diffFrames = (diff / 16.6667).toFixed(2);
      logger.log(`fully loaded in ${diff}ms (${diffFrames} frames)`);
    }
  }
  if (initialRender) {
    initialRender = false;
  }
};

// Parse JSON and report all abnormal JSON strings coming from BYOND
const parseStateJson = json => {
  let reviver = (key, value) => {
    if (typeof value === 'object' && value !== null) {
      if (value.__number__) {
        return parseFloat(value.__number__);
      }
    }
    return value;
  };
  // IE8: No reviver for you!
  // See: https://stackoverflow.com/questions/1288962
  if (tridentVersion <= 4) {
    reviver = undefined;
  }
  try {
    return JSON.parse(json, reviver);
  }
  catch (err) {
    // Try URL-decoding (BYOND may not decode url_encode output)
    try {
      const decoded = decodeURIComponent(String(json).replace(/\+/g, ' '));
      return JSON.parse(decoded, reviver);
    }
    catch (err2) {
      // ignore
    }
    const msg = err && err.message;
    throw new Error('JSON parsing error: ' + msg);
  }
};

const setupApp = () => {
  // Subscribe for redux state updates
  store.subscribe(() => {
    renderLayout();
  });

  // Subscribe for backend updates
  window.update = window.initialize = stateJson => {
    const state = parseStateJson(stateJson);
    store.dispatch(backendUpdate(state));
  };

  // Tell the server the page is ready and we want our initial data.
  // window.initialize is defined above so when the server calls output()
  // back it is caught immediately without queuing.
  // Also set the HTML flag so the fallback in tgui-main.html does not fire.
  if (window.__ref__) {
    window.__tgui_init_done = true;
    act(window.__ref__, 'tgui:initialize');
  }

  // Enable hot module reloading
  if (module.hot) {
    setupHotReloading();
    module.hot.accept(['./layout', './routes'], () => {
      renderLayout();
    });
  }

  // Process the early update queue
  while (true) {
    let stateJson = window.__updateQueue__.shift();
    if (!stateJson) {
      break;
    }
    window.update(stateJson);
  }

  // Dynamically load font-awesome from browser's cache
  loadCSS('font-awesome.css');
};

// IE8: Wait for DOM to properly load
if (tridentVersion <= 4 && document.readyState === 'loading') {
  document.addEventListener('DOMContentLoaded', setupApp);
}
else {
  setupApp();
}
