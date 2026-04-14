import os
import unittest


class TestDocs(unittest.TestCase):
    def test_readme_contains_new_menu_entries(self):
        with open(os.path.join('docs', 'README.md'), encoding='utf-8') as f:
            readme = f.read()
        self.assertIn('Arbeitsbeginn korrigieren', readme)
        self.assertIn('Arbeitsende korrigieren', readme)
        self.assertIn('Lässt du die Datumseingabe leer', readme)

    def test_readme_dev_mentions_date_prefill(self):
        with open(os.path.join('docs', 'README_DEV.md'), encoding='utf-8') as f:
            readme_dev = f.read()
        self.assertIn('Arbeitsbeginn korrigieren', readme_dev)
        self.assertIn('Arbeitsende korrigieren', readme_dev)
        self.assertIn('If the user leaves the date input empty', readme_dev)


if __name__ == '__main__':
    unittest.main()
