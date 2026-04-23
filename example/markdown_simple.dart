import 'package:nocterm/nocterm.dart';
import 'package:nocterm/src/components/markdown_component.dart';

void main() {
  runApp(SimpleMarkdownExample());
}

class SimpleMarkdownExample extends StatelessComponent {
  @override
  Component build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(2),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Markdown Syntax Highlighting Demo',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.cyan,
              ),
            ),
            const SizedBox(height: 2),
            MDown('''# Syntax Highlighting

This demo shows **syntax highlighted** code blocks using the `MDown` component.

## Dart

```dart
import 'package:flutter/material.dart';

class TodoApp extends StatefulWidget {
  const TodoApp({super.key});

  @override
  State<TodoApp> createState() => _TodoAppState();
}

class _TodoAppState extends State<TodoApp> {
  final List<String> _items = [];
  final _controller = TextEditingController();

  void _addItem() {
    if (_controller.text.isNotEmpty) {
      setState(() {
        _items.add(_controller.text);
        _controller.clear();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Todo App')),
      body: ListView.builder(
        itemCount: _items.length,
        itemBuilder: (context, index) => ListTile(
          title: Text(_items[index]),
        ),
      ),
    );
  }
}
```

## Python

```python
from dataclasses import dataclass
from typing import Optional

@dataclass
class User:
    name: str
    email: str
    age: Optional[int] = None

    def is_adult(self) -> bool:
        return self.age is not None and self.age >= 18

class UserRepository:
    def __init__(self, db_connection: str):
        self._conn = db_connection
        self._cache: dict[str, User] = {}

    async def get_user(self, user_id: str) -> Optional[User]:
        if user_id in self._cache:
            return self._cache[user_id]
        # Fetch from database
        user = await self._fetch(user_id)
        if user:
            self._cache[user_id] = user
        return user
```

## JavaScript

```javascript
const fetchUsers = async (filters = {}) => {
  try {
    const query = new URLSearchParams(filters);
    const response = await fetch(`/api/users?\$query`);

    if (!response.ok) {
      throw new Error(`HTTP \${response.status}`);
    }

    const { data, pagination } = await response.json();
    return { users: data, total: pagination.count };
  } catch (error) {
    console.error('Failed to fetch users:', error.message);
    return { users: [], total: 0 };
  }
};

export default function UserList() {
  const [users, setUsers] = useState([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    fetchUsers({ active: true })
      .then(({ users }) => setUsers(users))
      .finally(() => setLoading(false));
  }, []);

  return loading ? <Spinner /> : (
    <ul>
      {users.map(u => <li key={u.id}>{u.name}</li>)}
    </ul>
  );
}
```

## Rust

```rust
use std::collections::HashMap;
use tokio::sync::RwLock;

#[derive(Debug, Clone)]
struct CacheEntry<T> {
    value: T,
    expires_at: std::time::Instant,
}

pub struct Cache<T: Clone> {
    store: RwLock<HashMap<String, CacheEntry<T>>>,
    ttl: std::time::Duration,
}

impl<T: Clone> Cache<T> {
    pub fn new(ttl: std::time::Duration) -> Self {
        Self {
            store: RwLock::new(HashMap::new()),
            ttl,
        }
    }

    pub async fn get(&self, key: &str) -> Option<T> {
        let store = self.store.read().await;
        store.get(key).and_then(|entry| {
            if entry.expires_at > std::time::Instant::now() {
                Some(entry.value.clone())
            } else {
                None
            }
        })
    }

    pub async fn set(&self, key: String, value: T) {
        let entry = CacheEntry {
            value,
            expires_at: std::time::Instant::now() + self.ttl,
        };
        self.store.write().await.insert(key, entry);
    }
}
```

---

> Syntax highlighting powered by the `highlight` package.
> Supports **Dart**, **Python**, **JavaScript**, **Rust**, and many more languages!'''),
          ],
        ),
      ),
    );
  }
}
