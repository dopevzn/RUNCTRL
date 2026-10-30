import type { ReactNode } from 'react';
import './style.css';
export const metadata = {title:'RUNCTRL | Production Operations',description:'One command center for creative production teams'};
export default function RootLayout({children}:{children:ReactNode}){return <html lang="en"><body>{children}</body></html>}
