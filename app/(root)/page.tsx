import React from 'react';
import HeaderBox from '../../components/headerBox';
import TotalBalanceBox from '@/components/TotalBalanceBox';
import RightSidebar from '@/components/RightSidebar';
import { getLoggedInUser } from '@/lib/actions/user.actions';

const Home = async () => {
    const loggedIn = await getLoggedInUser();

    return (
        <section className='home'>
            <div className='home-content'>
                <header className='home-header'>
                    <HeaderBox
                        type='greeting'
                        title='Welcome'
                        user={loggedIn?.name || 'Guest'}
                        subtext='Acces and manage your account and transactiosn efficiently'
                    />
                    <TotalBalanceBox
                        accounts={[]}
                        totalBanks={1}
                        totalCurrentBalance={1000.85}
                    />
                </header>
                RECENT TRANSAC
            </div>
            <RightSidebar
                user={loggedIn}
                transactions={[]}
                banks={[
                    { currentBalance: 500.45, mask: '1234' },
                    { currentBalance: 1200, mask: '1234' },
                ]}
            />
        </section>
    );
};

export default Home;
