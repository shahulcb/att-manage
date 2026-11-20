// Fake company data used by the mock ERP endpoints AND the demo seed (keeps them consistent).
const people: [string, string, string][] = [
  ['Asha Kumar', 'Sales', 'asha'], ['Ravi Patel', 'Support', 'ravi'], ['Meena Iyer', 'Ops', 'meena'],
  ['Karthik Raj', 'Engineering', 'karthik'], ['Divya Nair', 'HR', 'divya'], ['Imran Khan', 'Sales', 'imran'],
  ['Sneha Reddy', 'Finance', 'sneha'], ['Arjun Mehta', 'Engineering', 'arjun'], ['Priya Singh', 'Support', 'priya'],
  ['Vikram Das', 'Ops', 'vikram'], ['Lakshmi Menon', 'Finance', 'lakshmi'], ['Rahul Verma', 'Engineering', 'rahul'],
];
export const MOCK_EMPLOYEES = people.map(([name, department, username], i) => ({
  id: `E${String(i + 1).padStart(3, '0')}`, name, username, department,
  email: `${username}@example.com`, phone: `90000000${String(i + 1).padStart(2, '0')}`, role: 'employee', active: true,
}));
export const MOCK_OWNER = { id: 'A001', name: 'The Boss', username: 'boss', department: 'Management', email: 'boss@example.com', phone: '', role: 'admin', active: true };
export const MOCK_EMP_PASSWORD = 'pass123';
export const MOCK_OWNER_PASSWORD = 'admin123';
