// Stimulus Mock
class MockController {
  constructor() {
    this.element = document.createElement('div');
    this.targets = [];
    this.values = {};
    this.data = new Map();
  }

  static get targets() {
    return [];
  }

  static get values() {
    return {};
  }

  connect() {}
  disconnect() {}

  // Mock target getters
  get hasTarget() {
    return (targetName) => {
      return this[`has${targetName.charAt(0).toUpperCase() + targetName.slice(1)}Target`] || false;
    };
  }
}

const Controller = MockController;

module.exports = {
  Controller,
};