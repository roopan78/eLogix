const { jestConfig } = require("@salesforce/sfdx-lwc-jest/config");

module.exports = {
  ...jestConfig,
  moduleNameMapper: {
    // Base components that @salesforce/sfdx-lwc-jest does not stub.
    "^lightning/modal$": "<rootDir>/jest-mocks/lightning/modal"
  },
  modulePathIgnorePatterns: ["<rootDir>/.localdevserver"]
};
