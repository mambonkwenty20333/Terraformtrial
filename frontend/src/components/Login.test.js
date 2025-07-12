import { render, screen } from '@testing-library/react';
import { BrowserRouter } from 'react-router-dom';
import Login from './Login';

const MockedLogin = ({ onLogin }) => (
  <BrowserRouter>
    <Login onLogin={onLogin} />
  </BrowserRouter>
);

test('renders login form', () => {
  render(<MockedLogin onLogin={() => {}} />);
  expect(screen.getByText(/Login/i)).toBeInTheDocument();
  expect(screen.getByLabelText(/Email/i)).toBeInTheDocument();
  expect(screen.getByLabelText(/Password/i)).toBeInTheDocument();
});