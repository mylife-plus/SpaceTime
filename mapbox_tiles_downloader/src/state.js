/**
 * State management for tracking download progress
 */

const path = require('path');
const { loadJSON, saveJSON } = require('./utils');

class StateManager {
  constructor(stateFilePath) {
    this.stateFilePath = stateFilePath;
    this.state = this.load();
  }

  /**
   * Load state from file
   * @returns {object} State object
   */
  load() {
    const defaultState = {
      version: '1.0.0',
      lastRun: null,
      totalDownloaded: 0,
      totalFailed: 0,
      zoomLevels: {},
      downloadHistory: [],
      quotaExceeded: false,
      usedFallback: false
    };
    
    return loadJSON(this.stateFilePath, defaultState);
  }

  /**
   * Save state to file
   */
  save() {
    saveJSON(this.stateFilePath, this.state);
  }

  /**
   * Initialize zoom level state
   * @param {number} zoom - Zoom level
   * @param {number} totalTiles - Total tiles for this zoom level
   */
  initZoomLevel(zoom, totalTiles) {
    if (!this.state.zoomLevels[zoom]) {
      this.state.zoomLevels[zoom] = {
        totalTiles: totalTiles,
        downloaded: 0,
        failed: 0,
        skipped: 0,
        completed: false,
        lastAttempt: null
      };
    }
  }

  /**
   * Update zoom level progress
   * @param {number} zoom - Zoom level
   * @param {object} progress - Progress data
   */
  updateZoomLevel(zoom, progress) {
    if (!this.state.zoomLevels[zoom]) {
      this.initZoomLevel(zoom, 0);
    }
    
    Object.assign(this.state.zoomLevels[zoom], progress);
    this.save();
  }

  /**
   * Mark zoom level as completed
   * @param {number} zoom - Zoom level
   */
  completeZoomLevel(zoom) {
    if (this.state.zoomLevels[zoom]) {
      this.state.zoomLevels[zoom].completed = true;
      this.state.zoomLevels[zoom].lastAttempt = new Date().toISOString();
      this.save();
    }
  }

  /**
   * Check if zoom level is completed
   * @param {number} zoom - Zoom level
   * @returns {boolean} True if completed
   */
  isZoomLevelCompleted(zoom) {
    return this.state.zoomLevels[zoom]?.completed || false;
  }

  /**
   * Get incomplete zoom levels
   * @param {array} allZoomLevels - All configured zoom levels
   * @returns {array} Incomplete zoom levels
   */
  getIncompleteZoomLevels(allZoomLevels) {
    return allZoomLevels.filter(zoom => !this.isZoomLevelCompleted(zoom));
  }

  /**
   * Record download session
   * @param {object} session - Session data
   */
  recordSession(session) {
    this.state.lastRun = new Date().toISOString();
    this.state.totalDownloaded += session.downloaded || 0;
    this.state.totalFailed += session.failed || 0;
    this.state.quotaExceeded = session.quotaExceeded || false;
    this.state.usedFallback = session.usedFallback || false;
    
    this.state.downloadHistory.push({
      timestamp: new Date().toISOString(),
      ...session
    });
    
    // Keep only last 50 sessions
    if (this.state.downloadHistory.length > 50) {
      this.state.downloadHistory = this.state.downloadHistory.slice(-50);
    }
    
    this.save();
  }

  /**
   * Get download statistics
   * @returns {object} Statistics
   */
  getStats() {
    const totalZoomLevels = Object.keys(this.state.zoomLevels).length;
    const completedZoomLevels = Object.values(this.state.zoomLevels)
      .filter(z => z.completed).length;
    
    const totalTiles = Object.values(this.state.zoomLevels)
      .reduce((sum, z) => sum + z.totalTiles, 0);
    const downloadedTiles = Object.values(this.state.zoomLevels)
      .reduce((sum, z) => sum + z.downloaded, 0);
    
    return {
      totalZoomLevels,
      completedZoomLevels,
      totalTiles,
      downloadedTiles,
      totalFailed: this.state.totalFailed,
      lastRun: this.state.lastRun,
      quotaExceeded: this.state.quotaExceeded,
      usedFallback: this.state.usedFallback,
      progress: totalTiles > 0 ? (downloadedTiles / totalTiles * 100).toFixed(2) : 0
    };
  }

  /**
   * Reset state
   */
  reset() {
    this.state = {
      version: '1.0.0',
      lastRun: null,
      totalDownloaded: 0,
      totalFailed: 0,
      zoomLevels: {},
      downloadHistory: [],
      quotaExceeded: false,
      usedFallback: false
    };
    this.save();
  }

  /**
   * Reset specific zoom level
   * @param {number} zoom - Zoom level
   */
  resetZoomLevel(zoom) {
    if (this.state.zoomLevels[zoom]) {
      delete this.state.zoomLevels[zoom];
      this.save();
    }
  }
}

module.exports = StateManager;

