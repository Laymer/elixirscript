module.exports = {
  rules: {
    camelcase: 'off',
    'no-bitwise': 'off',
    'no-plusplus': 'off',
    'no-restricted-syntax': 'off',
    'no-underscore-dangle': 'off',
    'import/extensions': 'off',
  },
  extends: 'airbnb-base',
  plugins: ['import'],
  env: {
    browser: true,
    node: true,
    mocha: true,
  },
};
